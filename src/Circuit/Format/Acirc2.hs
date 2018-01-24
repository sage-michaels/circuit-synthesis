{-# LANGUAGE OverloadedStrings #-}

module Circuit.Format.Acirc2 where

import Circuit
import Circuit.Conversion
import qualified Circuit.Format.Acirc as Acirc

import qualified Data.Text as T

showWithTests :: ToAcirc2 g => Circuit g -> [TestCase] -> T.Text
showWithTests c ts = T.append ":binary\n" (Acirc.showWithTests (toAcirc2 c) ts)

readWithTests :: Gate g => FilePath -> IO (Circuit g, [TestCase])
readWithTests = Acirc.readWithTests

read :: Gate g => FilePath -> IO (Circuit g)
read = Acirc.read