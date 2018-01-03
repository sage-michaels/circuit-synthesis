{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE BangPatterns #-}

module Circuit.Format.Acirc
  ( Circuit.Format.Acirc.read
  , Circuit.Format.Acirc.write
  , readAcirc
  , showWithTests
  , showCirc
  , parseCirc
  ) where

import Circuit
import Circuit.Parser
import Circuit.Utils hiding ((%))
import qualified Circuit.Builder           as B
import qualified Circuit.Builder.Internals as B

import Control.Monad.Trans (lift)
import Lens.Micro.Platform
import Text.Parsec hiding (spaces, parseTest)
import TextShow
import qualified Data.Text as T
import qualified Data.Text.IO as T

read :: FilePath -> IO Acirc
read = fmap fst . readAcirc

readAcirc :: FilePath -> IO (Acirc, [TestCase])
readAcirc fp = parseCirc <$> readFile fp

write :: FilePath -> Acirc -> IO ()
write fp c = T.writeFile fp (showCirc c)

showWithTests :: Acirc -> [TestCase] -> T.Text
showWithTests c ts = let s = showCirc c
                         t = T.unlines (map showTest ts)
                     in T.append t s

showCirc :: Acirc -> T.Text
showCirc !c = T.unlines (header ++ gateLines)
  where
    header = [ T.append ":symlen "  (showt (_circ_symlen c))
             , T.append ":base "    (showt (_circ_base c))
             , T.append ":ninputs " (showt (ninputs c))
             , T.append ":nconsts " (showt (nconsts c))
             , T.append ":outputs " (T.unwords (map (showt.getRef) (outputRefs c)))
             , T.append ":secrets " (T.unwords (map (showt.getRef) (secretRefs c)))
             , ":start"
             ]

    inputs = map gateTxt (inputRefs c)
    consts = map gateTxt (constRefs c)
    gates  = map gateTxt (gateRefs c)

    gateLines = concat [inputs, consts, gates]

    usage = timesUsed c

    gateTxt :: Ref -> T.Text
    gateTxt !ref =
        case c ^. circ_refmap . at (getRef ref) . non (error "[gateTxt] unknown ref") of
            (ArithInput id) -> T.concat [ showt (getRef ref), " input ", showt (getId id) ]
            (ArithConst id) ->
                let val = case c ^. circ_const_vals . at (getId id)  of
                                Nothing -> ""
                                Just y  -> showt y
                in T.concat [ showt (getRef ref), " const ", val ]
            (ArithAdd x y) -> pr ref "ADD" x y
            (ArithSub x y) -> pr ref "SUB" x y
            (ArithMul x y) -> pr ref "MUL" x y

    pr :: Ref -> T.Text -> Ref -> Ref -> T.Text
    pr !ref !gateTy !x !y =
        T.concat [ showt (getRef ref), " ", gateTy, " ", showt (getRef x), " ", showt (getRef y)
                 , " : ", showt (usage ^. at (getRef ref) . non 0) -- print times used
                 ]

showTest :: TestCase -> T.Text
showTest (!inp, !out) = T.concat [":test ", T.pack (showInts (reverse inp)), " "
                                 , T.pack (showInts (reverse out)) ]

--------------------------------------------------------------------------------
-- parser

type AcircParser = ParseCirc ArithGate ()

parseCirc :: String -> (Acirc, [TestCase])
parseCirc s = runCircParser () parser s
  where
    parser   = preamble >> lines >> eof
    preamble = many $ (char ':' >> (try parseTest <|> try parseSymlen <|> try parseBase <|>
                                    try parseOutputs <|> try parseSecrets <|> skipParam))
    lines    = many parseRefLine

skipParam :: AcircParser ()
skipParam = do
    skipMany (oneOf " \t" <|> alphaNum)
    endLine

parseTest :: AcircParser ()
parseTest = do
    string "test"
    spaces
    inps <- many digit
    spaces
    outs <- many digit
    let inp = readInts inps
        res = readInts outs
    addTest (reverse inp, reverse res)
    endLine

parseBase :: AcircParser ()
parseBase = do
    string "base"
    spaces
    n <- Prelude.read <$> many digit
    lift (B.setBase n)
    endLine

parseSymlen :: AcircParser ()
parseSymlen = do
    string "symlen"
    spaces
    n <- Prelude.read <$> many digit
    lift $ B.setSymlen n
    endLine

parseOutputs :: AcircParser ()
parseOutputs = do
    string "outputs"
    spaces
    refs <- many (do ref <- parseRef; spaces; return ref)
    lift $ mapM_ B.markOutput refs
    endLine

parseSecrets :: AcircParser ()
parseSecrets = do
    string "secrets"
    spaces
    secs <- many (do { ref <- parseRef; spaces; return ref })
    lift $ mapM B.markSecret secs
    endLine

parseRef :: AcircParser Ref
parseRef = Ref <$> Prelude.read <$> many1 digit

parseRefLine :: AcircParser ()
parseRefLine = do
    ref <- parseRef
    spaces
    choice [parseConst ref, parseInput ref, parseGate ref]
    endLine

parseInput :: Ref -> AcircParser ()
parseInput ref = do
    string "input"
    spaces
    id <- Id <$> Prelude.read <$> many1 digit
    lift $ B.insertInput ref id

parseConst :: Ref -> AcircParser ()
parseConst ref = do
    string "const"
    spaces
    val <- Prelude.read <$> many1 digit
    id  <- lift B.nextConstId
    lift $ B.insertConst ref id
    lift $ B.insertConstVal id val

parseGate :: Ref -> AcircParser ()
parseGate ref = do
    opType <- oneOfStr ["ADD", "SUB", "MUL"]
    spaces
    x <- Ref . Prelude.read <$> many1 digit
    spaces
    y <- Ref . Prelude.read <$> many1 digit
    let gate = case opType of
            "ADD" -> ArithAdd x y
            "MUL" -> ArithMul x y
            "SUB" -> ArithSub x y
            g     -> error ("[parser] unkonwn gate type " ++ g)
    lift $ B.insertGate ref gate
    optional $ spaces >> char ':' >> spaces >> int -- times used annotation
