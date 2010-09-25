{-# LANGUAGE DeriveDataTypeable #-}
module Main where
import TestExpr
import System.Console.CmdArgs
import Control.Monad

data Sample = Sample 
    { filename       :: String
    , max_iterations :: Int
    , show_classes   :: Bool
    , cost :: Bool
    }
  deriving (Show, Data, Typeable)

sample = Sample
    { filename = def &= help "file with code to optimise" &= typ "test.pec"
    , max_iterations = 123 &= help "max number of rounds with the optimiser"
    , show_classes = False &= help "print classes"
    , cost = False &= help "show the cost"
    }
  &= summary "PureEqSat v0.1, (C) Simon Edwardsson & Daniel Gustafsson 2010"
  &= program "PureEqSat"
  

main = do
    cmd <- cmdArgs sample
    res <- testFileExpr (filename cmd)
                                  (max_iterations cmd)
                                  (show_classes cmd)
    case res of
        Left err -> putStrLn $ "Error: " ++ err
        Right (score, expr) -> do
            print expr
            when (cost cmd) $ putStrLn ("Cost: " ++ show score)
