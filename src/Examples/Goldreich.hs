{-# LANGUAGE TupleSections #-}
{-# LANGUAGE CPP #-}
#if __GLASGOW_HASKELL__ >= 800
{-# LANGUAGE Strict #-}
#endif

module Examples.Goldreich where

import Circuit
import Circuit.Builder
import Circuit.Utils

import Control.Monad
import Control.Monad.Trans
import Data.Array.Unboxed
import Text.Printf

export :: Gate g => [(String, [IO (String, Circuit g)])]
export =
    [("goldreich", [ ("prg_xormaj_32_32"   ,) <$> prg'  32  32 5 xorMaj
                   , ("prg_xormaj_32_128"  ,) <$> prg'  32 128 5 xorMaj
                   , ("prg_xormaj_64_64"   ,) <$> prg'  64  64 6 xorMaj
                   , ("prg_xormaj_64_128"  ,) <$> prg'  64 128 6 xorMaj
                   , ("prg_xormaj_128_128" ,) <$> prg' 128 128 7 xorMaj

                   , ("prg_xorand_32_32"   ,) <$> prg'  32  32 5 xorAnd
                   , ("prg_xorand_32_128"  ,) <$> prg'  32 128 5 xorAnd
                   , ("prg_xorand_64_64"   ,) <$> prg'  64  64 5 xorAnd
                   , ("prg_xorand_64_128"  ,) <$> prg'  64 128 5 xorAnd
                   , ("prg_xorand_128_128" ,) <$> prg' 128 128 5 xorAnd
                   ])

    ,("prg_test", [("prg_test",) <$> prgTest])
    ]

--------------------------------------------------------------------------------
-- predicates

majority :: (Gate g, Monad m) => [Ref] -> BuilderT g m Ref
majority xs = lookupTable maj xs
  where
    maj xs = sum (map b2i xs) >= (length xs `div` 2)

xorMaj :: (Gate g, Monad m) => [Ref] -> BuilderT g m Ref
xorMaj xs = do
    let n = length xs `div` 2
    wl <- circXors (take n xs)
    -- wr <- majorityNaive (drop n xs)
    wr <- majority (drop n xs)
    circXor wl wr

xorAnd :: (Gate g, Monad m) => [Ref] -> BuilderT g m Ref
xorAnd (x0:x1:xs) = do
    y <- circAnd x0 x1
    circXors (y : xs)
xorAnd _ = error "[xorAnd] need at least three inputs!"

-- "Tri-sum-paired-and" from https://eprint.iacr.org/2017/277
tspa :: (Gate g, Monad m) => [Ref] -> BuilderT g m Ref
tspa [x1,x2,x3,x4,x5] = do
    w0 <- circXors [x1,x2,x3]
    w1 <- circXor x2 x4
    w2 <- circXor x3 x5
    w3 <- circMul w1 w2
    circXor w0 w3
tspa _ = error "[tspa] defined for locality 5"

--------------------------------------------------------------------------------
-- prg

prg :: Gate g => Int -> Int -> IO (Circuit g)
prg n m = prg' n m 5 xorAnd

prg' :: Gate g => Int -> Int -> Int -> ([Ref] -> BuilderT g IO Ref) -> IO (Circuit g)
prg' n m d predicate = buildCircuitT $ do
    xs <- inputs n
    g  <- prgBuilder n m d predicate
    zs <- g xs
    outputs zs

prgBuilder :: (Gate g, MonadIO m)
           => Int -> Int -> Int -> ([Ref] -> BuilderT g m Ref)
           -> BuilderT g m ([Ref] -> BuilderT g m [Ref])
prgBuilder ninputs noutputs locality predicate = fst <$> prgBuilder' ninputs noutputs locality predicate

prgBuilder' :: (Gate g, MonadIO m)
           => Int -> Int -> Int -> ([Ref] -> BuilderT g m Ref)
           -> BuilderT g m ([Ref] -> BuilderT g m [Ref], String)
prgBuilder' ninputs noutputs locality predicate = do
    selections <- safeChunksOf locality <$> (liftIO $ randIO $ randIntsMod (noutputs * locality) ninputs)
    let g xs = mapM predicate (map (selectsPT xs) selections)
        s    = prgDesc ninputs noutputs selections
    return (g, s)

--------------------------------------------------------------------------------
-- indexed prg

indexedPrg :: Gate g => Int -> Int -> Int -> IO (Circuit g)
indexedPrg ninputs noutputs outputSize = buildCircuitT $ do
    xs  <- inputs ninputs
    ix  <- inputs (numBits noutputs)
    sel <- selectionVector ix
    g   <- indexedPrgSigmaBuilder ninputs noutputs outputSize
    outputs =<< g xs sel

indexedPrgSigma :: Gate g => Int -> Int -> Int -> IO (Circuit g)
indexedPrgSigma ninputs noutputs outputSize = buildCircuitT $ do
    xs <- inputs ninputs
    ix <- inputs noutputs
    g  <- indexedPrgSigmaBuilder ninputs noutputs outputSize
    outputs =<< g xs ix

indexedPrgNaiveSigma :: Gate g => Int -> Int -> Int -> IO (Circuit g)
indexedPrgNaiveSigma ninputs noutputs outputSize = buildCircuitT $ do
    xs <- inputs ninputs
    ix <- inputs noutputs
    g  <- prgBuilder ninputs (noutputs*outputSize) 5 xorAnd
    zs <- g xs
    outputs =<< selectListSigma ix (safeChunksOf outputSize zs)

-- TODO: do this more efficiently; lists are expensive
indexedPrgSigmaBuilder :: (Gate g, MonadIO m) => Int -> Int -> Int
                       -> BuilderT g m ([Ref] -> [Ref] -> BuilderT g m [Ref])
indexedPrgSigmaBuilder ninputs noutputs outputSize = do
    -- for each bit of the output, 5 random bits
    selsList <- liftIO $ randIO $ replicateM (5*noutputs*outputSize) (randIntMod ninputs)
    let selections = listArray ((0,0), (noutputs*outputSize-1, 4)) selsList :: UArray (Int,Int) Int
    return $ \xs ix -> do
        when (length ix /= noutputs) $ error $
            printf "[indexedPrgSigmaBuilder::closure] wrong length index! wanted %d, but got %d" noutputs (length ix)

        when (length xs /= ninputs) $ error $
            printf "[indexedPrgSigmaBuilder::closure] wrong length input! wanted %d, but got %d" ninputs (length xs)

        let xs' = listArray (0,length xs-1) (map getRef xs) :: UArray Int Int

        inps <- forM [0..outputSize-1] $ \i -> do -- for each output bit i

            forM [0..4] $ \j -> do                -- for each input bit of each output bit

                sels <- forM (zip [0..noutputs-1] ix) $ \(k, ix_k) -> do -- for each output group
                    let sel = selections ! (outputSize*k+i, j)
                    circMul ix_k (Ref (xs' ! sel))

                foldM1 circAdd sels

        mapM xorAnd inps

--------------------------------------------------------------------------------
-- prg description

prgDesc :: Int -> Int -> [[Int]] -> String
prgDesc nin nout selections =
    printf "nin=%d nout=%d\n" nin nout ++
    unlines (map (unwords . map show) selections)

prgTest :: Gate g => IO (Circuit g)
prgTest = buildCircuitT $ do
    let ninputs = 16
        noutputs = ninputs*2
    x <- inputs ninputs
    (g, desc) <- prgBuilder' ninputs noutputs 5 xorAnd
    outputs =<< g x
    lift $ writeFile "prg_test.txt" desc
