{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE Strict #-}

import Circuit
import Circuit.Builder
import qualified Circuit.Format.Acirc as Acirc
import Util
import Rand

import Control.Monad
import Data.List.Split
import Debug.Trace

--------------------------------------------------------------------------------
-- f1

majorityNaive :: [Ref] -> Builder Ref
majorityNaive xs = do
    let cs = combinations (length xs `div` 2) xs
    zs <- mapM circProd cs
    circOrs zs

majority :: [Ref] -> Builder Ref
majority xs = lookupTable maj xs
  where
    maj xs = sum (map b2i xs) >= (length xs `div` 2)

xorMaj :: [Ref] -> Builder Ref
xorMaj xs = do
    let n = length xs `div` 2
    wl <- circXors (take n xs)
    -- wr <- majorityNaive (drop n xs)
    wr <- majority (drop n xs)
    circXor wl wr

-- select the ix'th bit from x
select :: [Ref] -> [Ref] -> Builder Ref
select xs ix = do
    sel <- selectionVector ix
    zs  <- zipWithM (circMul) sel xs
    circSum zs

selects :: [Ref] -> [[Ref]] -> Builder [Ref]
selects xs ixs = mapM (select xs) ixs

f1 :: Int -> Int -> IO Circuit
f1 n m = do
    keyBits <- randKeyIO n
    return $ buildCircuit $ do
        let l = ceiling (logBase 2 (fromIntegral n))
            d = l
        key <- secrets keyBits
        zs  <- replicateM m $ do
            xs <- replicateM d (inputs l)
            bs <- selects key xs
            xorMaj bs
        outputs zs

f1_rachel :: Int -> Int -> IO Circuit
f1_rachel n m = do
    keyBits <- randKeyIO n
    return $ buildCircuit $ do
        let d = ceiling (logBase 2 (fromIntegral n))
        key <- secrets keyBits
        zs  <- replicateM m $ do
            xs <- replicateM d (inputs n)
            bs <- mapM (zipWithM circMul key) xs
            zs <- mapM circSum bs
            xorMaj zs
        outputs zs

maj8n :: Circuit
maj8n = buildCircuit (output =<< majorityNaive =<< inputs 8)

maj8 :: Circuit
maj8 = buildCircuit (output =<< majority =<< inputs 8)

xormaj16 :: Circuit
xormaj16 = buildCircuit (output =<< xorMaj =<< inputs 16)

f1_128 :: IO Circuit
f1_128 = f1 128 1

--------------------------------------------------------------------------------
-- f2

f2 :: Int -> Int -> IO Circuit
f2 n m = do
    keyBits <- randKeyIO (2*n)
    return $ buildCircuit $ do
        let l = ceiling (logBase 2 (fromIntegral n))
            d = l
        kf <- secrets (take n keyBits)
        ke <- secrets (drop n keyBits)
        zs <- replicateM m $ do
            xs <- replicateM d (inputs l)
            bs <- selects kf xs
            xorMaj bs
        outputs zs

ext :: Int -> Int -> Circuit
ext n m = buildCircuit $ do
    let d = ceiling (logBase 2 (fromIntegral n))
        nrows = m
        ncols = n
    a <- replicateM nrows (inputs ncols)
    x <- inputs ncols
    z <- matrixTimesVect a x
    -- z <- matrixTimesVectLookup a x
    outputs z

-- xors :: Int -> Circuit
-- xors n = buildCircuit $ do
--     xs <- inputs n
--     z  <- circXors xs
--     output z

-- xors' :: Int -> Circuit
-- xors' n = buildCircuit $ do
--     xs <- inputs n
--     let xor True True = False
--         xor False True = True
--         xor True False = True
--         xor False False = False
--     z  <- lookupTable (foldl1 xor) xs
--     output z

--------------------------------------------------------------------------------
-- prg

selectsPt :: [Int] -> [Ref] -> Builder [Ref]
selectsPt sels xs = return (map (xs!!) sels)

prg :: Int -> Int -> IO Circuit
prg n m = do
    let l = ceiling (logBase 2 (fromIntegral n))
        d = l
    selections <- replicateM m $ replicateM d (randIO (randIntegerMod (fromIntegral n)))
    return $ buildCircuit $ do
        xs  <- inputs n
        zs  <- forM selections $ \s -> xorMaj =<< selectsPt (map fromIntegral s) xs
        outputs zs
