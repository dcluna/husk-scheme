{- |
Module      : Main
Copyright   : Justin Ethier
Licence     : MIT (see LICENSE in the distribution)

Maintainer  : github.com/justinethier
Stability   : experimental
Portability : portable

A front-end for an experimental compiler
-}

module Main where
import Paths_husk_scheme
import Language.Scheme.Compiler
import qualified Language.Scheme.Core
import Language.Scheme.Types     -- Scheme data types
import Language.Scheme.Variables -- Scheme variable operations
import Control.Monad.Error
import System.Cmd (system)
import System.Console.GetOpt
import System.FilePath (dropExtension)
import System.Environment
import System.Exit (ExitCode (..), exitWith, exitFailure)
import System.IO

main :: IO ()
main = do 

  putStrLn ""
  putStrLn "!!! This version of huskc is Experimental !!!"
  putStrLn ""
  putStrLn "It is recommended you consult the issue list prior to use:"
  putStrLn "https://github.com/justinethier/husk-scheme/issues"
  putStrLn ""

  -- Read command line args and process options
  args <- getArgs
  let (actions, nonOpts, msgs) = getOpt Permute options args
  opts <- foldl (>>=) (return defaultOptions) actions
  let Options {optOutput = output} = opts

  if null nonOpts
     then showUsage
     else do
        let inFile = nonOpts !! 0
            outExec = case output of
              Just inFile -> inFile
              Nothing -> dropExtension inFile
        process inFile outExec

-- 
-- For an explanation of the command line options code, see:
-- http://leiffrenzel.de/papers/commandline-options-in-haskell.html
--

-- |Data type to handle command line options that take parameters
data Options = Options {
    optOutput :: Maybe String -- Executable file to write
    }

-- |Default values for the command line options
defaultOptions :: Options
defaultOptions = Options {
    optOutput = Nothing 
    }

-- |Command line options
options :: [OptDescr (Options -> IO Options)]
options = [
  Option ['V'] ["version"] (NoArg showVersion) "show version number",
  Option ['h', '?'] ["help"] (NoArg showHelp) "show usage information",
  Option ['o'] ["output"] (ReqArg writeExec "FILE") "output file to write"
  ]

-- |Determine executable file to write. 
--  This version just takes a name from the command line option
writeExec arg opt = return opt { optOutput = Just arg }

-- TODO: would nice to have this as well as a 'real' usage printout, perhaps via --help

-- |Print a usage message
showUsage :: IO ()
showUsage = do
  putStrLn "huskc: no input files"

showHelp :: Options -> IO Options
showHelp _ = do
  putStrLn "Usage: huskc [options] file"
  putStrLn ""
  putStrLn "Options:"
  putStrLn "  --help                Display this information"
  putStrLn "  --version             Display husk version information"
  putStrLn "  --output filename     Write executable to the given filename"
  putStrLn ""
  exitWith ExitSuccess

-- |Print version information
showVersion :: Options -> IO Options
showVersion _ = do
  putStrLn Language.Scheme.Core.version
-- TODO: would be nice to be able to print the banner:  Language.Scheme.Core.showBanner
  exitWith ExitSuccess

-- |High level code to compile the given file
process :: String -> String -> IO ()
process inFile outExec = do
  env <- liftIO $ nullEnv
  stdlib <- getDataFileName "stdlib.scm"
  result <- (runIOThrows $ liftM show $ compileSchemeFile env stdlib inFile)
  case result of
   "" -> compileHaskellFile outExec
   _ -> putStrLn result

-- |Compile a scheme file to haskell
compileSchemeFile :: Env -> String -> String -> IOThrowsError LispVal
compileSchemeFile env stdlib filename = do
  -- TODO: it is only temporary to compile the standard library each time. It should be 
  --       precompiled and just added during the ghc compilation
  libsC <- compileLisp env stdlib "run" (Just "exec")
  execC <- compileLisp env filename "exec" Nothing
  outH <- liftIO $ openFile "_tmp.hs" WriteMode
  _ <- liftIO $ writeList outH header
  _ <- liftIO $ writeList outH $ map show libsC
  _ <- liftIO $ writeList outH $ map show execC
  _ <- liftIO $ hClose outH
  if not (null execC)
     then return $ Nil "" -- Dummy value
     else throwError $ Default "Empty file" --putStrLn "empty file"

-- |Compile the intermediate haskell file using GHC
compileHaskellFile :: String -> IO() --ThrowsError LispVal
compileHaskellFile filename = do
  let ghc = "ghc" -- Need to make configurable??
  compileStatus <- system $ ghc ++ " -cpp --make -package ghc -fglasgow-exts -o " ++ filename ++ " _tmp.hs"

-- TODO: delete intermediate hs files if requested

  case compileStatus of
    ExitFailure _code -> exitWith compileStatus
    ExitSuccess -> return ()

-- |Helper function to write a list of abstract Haskell code to file
writeList outH (l : ls) = do
  hPutStrLn outH l
  writeList outH ls
writeList outH _ = do
  hPutStr outH ""

