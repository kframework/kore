{- |
Copyright   : (c) Runtime Verification, 2020
License     : NCSA
-}

module Options.SMT
    ( KoreSolverOptions (..)
    , Solver (..)
    , parseKoreSolverOptions
    , unparseKoreSolverOptions
    , defaultSmtPreludeFilePath
    ) where

import Prelude.Kore

import qualified Data.Char as Char
import Data.List
    ( intercalate
    )
import Options.Applicative
    ( Parser
    , auto
    , help
    , long
    , metavar
    , option
    , readerError
    , str
    , strOption
    , value
    )
import qualified Options.Applicative as Options

import Data.Limit
    ( Limit (..)
    , maybeLimit
    )
import SMT hiding
    ( Solver
    )

data KoreSolverOptions = KoreSolverOptions
    { timeOut :: !TimeOut
    , resetInterval :: !ResetInterval
    , prelude :: !Prelude
    , solver :: !Solver
    }

parseKoreSolverOptions :: Parser KoreSolverOptions
parseKoreSolverOptions =
    KoreSolverOptions
    <$> option readSMTTimeOut
        ( metavar "SMT_TIMEOUT"
        <> long "smt-timeout"
        <> help "Timeout for calls to the SMT solver, in milliseconds"
        <> value defaultTimeOut
        )
    <*> option readSMTResetInterval
        ( metavar "SMT_RESET_INTERVAL"
        <> long "smt-reset-interval"
        <> help "Reset the solver after this number of queries"
        <> value defaultResetInterval
        )
    <*>
        (Prelude <$>
            optional
            ( strOption
                ( metavar "SMT_PRELUDE"
                <> long "smt-prelude"
                <> help "Path to the SMT prelude file"
                )
            )
        )
    <*> parseSolver
  where
    SMT.Config { timeOut = defaultTimeOut } = SMT.defaultConfig
    SMT.Config { resetInterval = defaultResetInterval } = SMT.defaultConfig

    readPositiveInteger ctor optionName = do
        readInt <- auto
        when (readInt <= 0) err
        return . ctor $ readInt
      where
        err =
            readerError
            . unwords
            $ [optionName, "must be a positive integer."]

    readSMTTimeOut = readPositiveInteger (SMT.TimeOut . Limit) "smt-timeout"
    readSMTResetInterval =
        readPositiveInteger SMT.ResetInterval "smt-reset-interval"

unparseKoreSolverOptions :: KoreSolverOptions -> [String]
unparseKoreSolverOptions
    KoreSolverOptions
        { timeOut = TimeOut unwrappedTimeOut
        , resetInterval
        , prelude = Prelude unwrappedPrelude
        , solver
        }
  =
    catMaybes
        [ (\limit -> unwords ["--smt-timeout", show limit])
            <$> maybeLimit Nothing Just unwrappedTimeOut
        , pure $ unwords ["--smt-reset-interval", show resetInterval]
        , unwrappedPrelude $> unwords ["--smt-prelude", defaultSmtPreludeFilePath]
        , pure $ "--smt " <> fmap Char.toLower (show solver)
        ]

-- | Available SMT solvers
data Solver = Z3 | None
    deriving (Eq, Ord, Show)
    deriving (Enum, Bounded)

parseSolver :: Parser Solver
parseSolver =
    option (snd <$> readSum longName options)
    $  metavar "SOLVER"
    <> long longName
    <> help ("SMT solver for checking constraints: " <> knownOptions)
    <> value Z3
  where
    longName = "smt"
    knownOptions = intercalate ", " (map fst options)
    options = [ (map Char.toLower $ show s, s) | s <- [minBound .. maxBound] ]

readSum :: String -> [(String, value)] -> Options.ReadM (String, value)
readSum longName options = do
    opt <- str
    case lookup opt options of
        Just val -> pure (opt, val)
        _ -> readerError (unknown opt ++ known)
  where
    knownOptions = intercalate ", " (map fst options)
    unknown opt = "Unknown " ++ longName ++ " '" ++ opt ++ "'. "
    known = "Known " ++ longName ++ "s are: " ++ knownOptions ++ "."


defaultSmtPreludeFilePath :: FilePath
defaultSmtPreludeFilePath = "prelude.smt2"
