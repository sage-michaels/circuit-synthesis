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
import qualified Data.Vector as V

tribes :: Int -> [Ref] -> Ref -> Builder Ref
tribes k y z = circXor z =<< circOrs =<< mapM circProd (chunksOf k y)

fa :: Int -> Int -> IO Circuit
fa n k = do
    keyBits <- randKeyIO ((n+1)^2)
    return $ buildCircuit $ do
        a <- chunksOf (n+1) <$> secrets keyBits
        x <- inputs (n+1)
        w <- matrixTimesVect a x
        z <- tribes k (init w) (last w)
        output z

fa_128 :: IO Circuit
fa_128 = fa 128 4

--------------------------------------------------------------------------------
-- trying to use lookup for matrix mul

matrixTimesVectBool :: Int -> Int -> [Bool] -> [Bool]
matrixTimesVectBool nrows ncols elems =
    if not $ all ((== ncols) . length) rows
       then error "[matrixTimesVect] bad dimensions"
       else map (foldl1 xor . zipWith (&&) vect) rows
  where
    n = length elems
    rows = chunksOf ncols (take (n - ncols) elems)
    vect = drop (n - ncols) elems

    xor True True = False
    xor False True = True
    xor True False = True
    xor False False = False

matrixTimesVectLookup :: [[Ref]] -> [Ref] -> Builder [Ref]
matrixTimesVectLookup rows vect =
    if length vect /= ncols
       then error "[matrixTimesVectLookup] bad dimensions"
       else lookupTableMultibit nrows (matrixTimesVectBool nrows ncols) refs
  where
    nrows = length rows
    ncols = length (head rows)
    refs = concat rows ++ vect

matrixTest :: Int -> Circuit
matrixTest n = buildCircuit $ do
    a <- replicateM n (inputs n)
    x <- inputs n
    z <- matrixTimesVect a x
    -- z <- matrixTimesVectLookup a x
    outputs z
