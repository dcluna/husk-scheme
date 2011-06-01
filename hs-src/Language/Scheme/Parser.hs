{- |
Module      : Language.Scheme.Parser
Copyright   : Justin Ethier
Licence     : MIT (see LICENSE in the distribution)

Maintainer  : github.com/justinethier
Stability   : experimental
Portability : portable

husk scheme interpreter

A lightweight dialect of R5RS scheme.

This module implements parsing of Scheme code.
-}

module Language.Scheme.Parser where
import Language.Scheme.Types
import Control.Monad.Error
import Char
import Complex
import Data.Array
import Numeric
import Ratio
import Text.ParserCombinators.Parsec hiding (spaces)

symbol :: Parser Char
symbol = oneOf "!$%&|*+-/:<=>?@^_~"

spaces :: Parser ()
spaces = skipMany1 space

parseAtom :: Parser LispVal
parseAtom = do
  first <- letter <|> symbol <|> (oneOf ".")
  rest <- many (letter <|> digit <|> symbol <|> (oneOf "."))
  let atom = first : rest
  if atom == "."
     then pzero -- Do not match this form
     else return $ Atom atom

parseBool :: Parser LispVal
parseBool = do _ <- string "#"
               x <- oneOf "tf"
               return $ case x of
                          't' -> Bool True
                          'f' -> Bool False
                          _ -> Bool False

parseChar :: Parser LispVal
parseChar = do
  _ <- try (string "#\\")
  c <- anyChar
  r <- many (letter)
  let pchr = c : r
  return $ case pchr of
    "space" -> Char ' '
    "newline" -> Char '\n'
    _ -> Char c

parseOctalNumber :: Parser LispVal
parseOctalNumber = do
  _ <- try (string "#o")
  sign <- many (oneOf "-")
  num <- many1 (oneOf "01234567")
  case (length sign) of
     0 -> return $ Number $ fst $ Numeric.readOct num !! 0
     1 -> return $ Number $ fromInteger $ (*) (-1) $ fst $ Numeric.readOct num !! 0
     _ -> pzero

parseBinaryNumber :: Parser LispVal
parseBinaryNumber = do
  _ <- try (string "#b")
  sign <- many (oneOf "-")
  num <- many1 (oneOf "01")
  case (length sign) of
     0 -> return $ Number $ fst $ Numeric.readInt 2 (`elem` "01") Char.digitToInt num !! 0
     1 -> return $ Number $ fromInteger $ (*) (-1) $ fst $ Numeric.readInt 2 (`elem` "01") Char.digitToInt num !! 0
     _ -> pzero

parseHexNumber :: Parser LispVal
parseHexNumber = do
  _ <- try (string "#x")
  sign <- many (oneOf "-")
  num <- many1 (digit <|> oneOf "abcdefABCDEF")
  case (length sign) of
     0 -> return $ Number $ fst $ Numeric.readHex num !! 0
     1 -> return $ Number $ fromInteger $ (*) (-1) $ fst $ Numeric.readHex num !! 0
     _ -> pzero

-- |Parser for Integer, base 10
parseDecimalNumber :: Parser LispVal
parseDecimalNumber = do
  _ <- try (many (string "#d"))
  sign <- many (oneOf "-")
  num <- many1 (digit)
  if (length sign) > 1
     then pzero
     else return $ (Number . read) $ sign ++ num

parseNumber :: Parser LispVal
parseNumber = parseDecimalNumber <|>
              parseHexNumber <|>
              parseBinaryNumber <|>
              parseOctalNumber <?>
              "Unable to parse number"

{- Parser for floating points
 - -}
parseRealNumber :: Parser LispVal
parseRealNumber = do
  sign <- many (oneOf "-")
  num <- many1 (digit)
  _ <- char '.'
  frac <- many1 (digit)
  let dec = num ++ "." ++ frac
  case (length sign) of
     0 -> do
              let numbr = fst $ Numeric.readFloat dec !! 0
-- expnt <- try (char 'e')
              return $ Float $ numbr
{- FUTURE: Issue #14: parse numbers in format #e1e10
 -
              expnt <- try (char 'e')
              case expnt of
--                'e' -> return $ Float $ numbr
                _ -> return $ Float $ numbr
return $ Float $ fst $ Numeric.readFloat dec !! 0 -}
     1 -> return $ Float $ (*) (-1.0) $ fst $ Numeric.readFloat dec !! 0
     _ -> pzero

parseRationalNumber :: Parser LispVal
parseRationalNumber = do
  pnumerator <- parseDecimalNumber
  case pnumerator of
    Number n -> do
      _ <- char '/'
      sign <- many (oneOf "-")
      num <- many1 (digit)
      if (length sign) > 1
         then pzero
         else return $ Rational $ n % (read $ sign ++ num)
    _ -> pzero

parseComplexNumber :: Parser LispVal
parseComplexNumber = do
  lispreal <- (try (parseRealNumber) <|> try (parseRationalNumber) <|> parseDecimalNumber)
  let real = case lispreal of
                  Number n -> fromInteger n
                  Rational r -> fromRational r
                  Float f -> f
                  _ -> 0
  _ <- char '+'
  lispimag <- (try (parseRealNumber) <|> try (parseRationalNumber) <|> parseDecimalNumber)
  let imag = case lispimag of
                  Number n -> fromInteger n
                  Rational r -> fromRational r
                  Float f -> f
                  _ -> 0 -- Case should never be reached
  _ <- char 'i'
  return $ Complex $ real :+ imag

parseEscapedChar :: forall st .
                    GenParser Char st Char
parseEscapedChar = do
  _ <- char '\\'
  c <- anyChar
  return $ case c of
    'n' -> '\n'
    't' -> '\t'
    'r' -> '\r'
    _ -> c

parseString :: Parser LispVal
parseString = do
  _ <- char '"'
  x <- many (parseEscapedChar <|> noneOf ("\""))
  _ <- char '"'
  return $ String x

parseVector :: Parser LispVal
parseVector = do
  vals <- sepBy parseExpr spaces
  return $ Vector (listArray (0, (length vals - 1)) vals)

parseList :: Parser LispVal
parseList = liftM List $ sepBy parseExpr spaces

parseDottedList :: Parser LispVal
parseDottedList = do
  phead <- endBy parseExpr spaces
  ptail <- char '.' >> spaces >> parseExpr
  return $ DottedList phead ptail

parseQuoted :: Parser LispVal
parseQuoted = do
  _ <- char '\''
  x <- parseExpr
  return $ List [Atom "quote", x]

parseQuasiQuoted :: Parser LispVal
parseQuasiQuoted = do
  _ <- char '`'
  x <- parseExpr
  return $ List [Atom "quasiquote", x]

parseUnquoted :: Parser LispVal
parseUnquoted = do
  _ <- try (char ',')
  x <- parseExpr
  return $ List [Atom "unquote", x]

parseUnquoteSpliced :: Parser LispVal
parseUnquoteSpliced = do
  _ <- try (string ",@")
  x <- parseExpr
  return $ List [Atom "unquote-splicing", x]


{- Comment parser
FUTURE: this is a hack, it should really not return anything...
a better solution might be to use a tokenizer as a
parser instead; need to investigate eventually. -}
parseComment :: Parser LispVal
parseComment = do
  _ <- char ';'
  _ <- many (noneOf ("\n"))
  return $ Nil ""


parseExpr :: Parser LispVal
parseExpr =
      try (parseComplexNumber)
  <|> try (parseRationalNumber)
  <|> parseComment
  <|> try (parseRealNumber)
  <|> try (parseNumber)
  <|> parseChar
  <|> parseUnquoteSpliced
  <|> do _ <- try (string "#(")
         x <- parseVector
         _ <- char ')'
         return x
  <|> try (parseAtom)
  <|> parseString
  <|> parseBool
  <|> parseQuoted
  <|> parseQuasiQuoted
  <|> parseUnquoted
  <|> do _ <- char '('
         x <- try parseList <|> parseDottedList
         _ <- char ')'
         return x
  <?> "Expression"

readOrThrow :: Parser a -> String -> ThrowsError a
readOrThrow parser input = case parse parser "lisp" input of
  Left err -> throwError $ Parser err
  Right val -> return val

readExpr :: String -> ThrowsError LispVal
readExpr = readOrThrow parseExpr

readExprList :: String -> ThrowsError [LispVal]
readExprList = readOrThrow (endBy parseExpr spaces)
