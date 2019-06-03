{-# OPTIONS_GHC -Wno-unused-top-binds    #-}
-- Added for outputFileName

module Main (main) where

import           Control.Applicative
                 ( optional )
import           Control.Concurrent.MVar
import qualified Data.Bifunctor as Bifunctor
import           Data.Semigroup
                 ( (<>) )
import           Options.Applicative
                 ( InfoMod, Parser, argument, auto, flag, fullDesc, header,
                 help, long, metavar, option, progDesc, readerError, short,
                 str, strOption, value )
import           System.Exit
                 ( exitFailure )

import           Data.Limit
                 ( Limit (..) )
import qualified Kore.Builtin as Builtin
import           Kore.Exec
                 ( proveWithRepl )
import qualified Kore.IndexedModule.IndexedModule as IndexedModule
import           Kore.Logger.Output
                 ( emptyLogger, swappableLogger )
import           Kore.Repl
import           Kore.Step.Simplification.Data
                 ( evalSimplifier )
import           Kore.Syntax.Module
                 ( ModuleName (..) )

import           GlobalMain
import qualified SMT as SMT

-- | Represents a file name along with its module name passed.
data KoreModule = KoreModule
    { fileName   :: !FilePath
    , moduleName :: !ModuleName
    }

-- | SMT Timeout and (optionally) a custom prelude path.
data SmtOptions = SmtOptions
    { timeOut :: !SMT.TimeOut
    , prelude :: !(Maybe FilePath)
    }

-- | Options for the kore repl.
data KoreReplOptions = KoreReplOptions
    { definitionModule :: !KoreModule
    , proveOptions     :: !KoreProveOptions
    , smtOptions       :: !SmtOptions
    , replMode         :: !ReplMode
    , replScript       :: !ReplScript
    }

parseKoreReplOptions :: Parser KoreReplOptions
parseKoreReplOptions =
    KoreReplOptions
    <$> parseMainModule
    <*> parseKoreProveOptions
    <*> parseSmtOptions
    <*> parseReplMode
    <*> parseReplScript
    <* parseIgnoredOutput
  where
    parseMainModule :: Parser KoreModule
    parseMainModule  =
        KoreModule
        <$> argument str
            (  metavar ("MAIN_DEFINITION_FILE")
            <> help "Kore definition file to verify and use for execution"
            )
        <*> parseModuleName "MAIN" "Kore main module name." "module"

    parseModuleName :: String -> String -> String -> Parser ModuleName
    parseModuleName name helpMessage longName =
        ModuleName
        <$> strOption
            (  metavar (name <> "_MODULE")
            <> long longName
            <> help helpMessage
            )

    parseSmtOptions :: Parser SmtOptions
    parseSmtOptions =
        SmtOptions
        <$> option readSMTTimeOut
            (  metavar "SMT_TIMEOUT"
            <> long "smt-timeout"
            <> help "Timeout for calls to the SMT solver, in miliseconds"
            <> value defaultTimeOut
            )
        <*> optional
            ( strOption
                (  metavar "SMT_PRELUDE"
                <> long "smt-prelude"
                <> help "Path to the SMT prelude file"
                )
            )

    parseReplMode :: Parser ReplMode
    parseReplMode =
        flag
            Interactive
            RunScript
            ( long "run-mode"
            <> short 'r'
            <> help "Repl run script mode"
            )

    parseReplScript :: Parser ReplScript
    parseReplScript =
        ReplScript
        <$> optional
            ( strOption
                ( metavar "REPL_SCRIPT"
                <> long "repl-script"
                <> help "Path to the repl script file"
                )
            )

    SMT.Config { timeOut = defaultTimeOut } = SMT.defaultConfig

    readSMTTimeOut = do
        i <- auto
        if i <= 0
            then readerError "smt-timeout must be a positive integer."
            else return $ SMT.TimeOut $ Limit i

    parseIgnoredOutput :: Parser (Maybe String)
    parseIgnoredOutput =
        optional
            (strOption
                (  metavar "PATTERN_OUTPUT_FILE"
                <> long "output"
                <> help "This parameter is ignored"
                )
            )

parserInfoModifiers :: InfoMod options
parserInfoModifiers =
    fullDesc
    <> progDesc "REPL debugger for proofs"
    <> header "kore-repl - a repl for Kore proofs"

main :: IO ()
main = do
    options <- mainGlobal parseKoreReplOptions parserInfoModifiers
    case localOptions options of
        Nothing -> pure ()
        Just koreReplOptions -> mainWithOptions koreReplOptions

mainWithOptions :: KoreReplOptions -> IO ()
mainWithOptions
    KoreReplOptions
        { definitionModule, proveOptions, smtOptions, replScript, replMode }
  = do
    parsedDefinition <- parseDefinition definitionFileName
    indexedDefinition@(indexedModules, _) <-
        verifyDefinitionWithBase
            Nothing
            True
            parsedDefinition
    indexedModule <-
        constructorFunctions <$> mainModule mainModuleName indexedModules

    specDef <- parseDefinition specFile
    let unverifiedDefinition =
            Bifunctor.first
                ((fmap . IndexedModule.mapPatterns)
                    Builtin.externalizePattern
                )
                indexedDefinition
    (specDefIndexedModules, _) <-
        verifyDefinitionWithBase
            (Just unverifiedDefinition)
            True
            specDef
    specDefIndexedModule <-
        mainModule specModule specDefIndexedModules

    let
        smtConfig =
            SMT.defaultConfig
                { SMT.timeOut = smtTimeOut
                , SMT.preludeFile = smtPrelude
                }
    if replMode == RunScript && (unReplScript replScript) == Nothing
        then do
            putStrLn
                "You must supply the path to the repl script\
                \ in order to run the repl in run-script mode."
            exitFailure
        else do
            mLogger <- newMVar emptyLogger
            SMT.runSMT smtConfig (swappableLogger mLogger)
               $ evalSimplifier
               $ proveWithRepl
                    indexedModule
                    specDefIndexedModule
                    mLogger
                    replScript
                    replMode

  where
    mainModuleName :: ModuleName
    mainModuleName = moduleName definitionModule

    definitionFileName :: FilePath
    definitionFileName = fileName definitionModule

    specModule :: ModuleName
    specModule = specMainModule proveOptions

    specFile :: FilePath
    specFile = specFileName proveOptions

    smtTimeOut :: SMT.TimeOut
    smtTimeOut = timeOut smtOptions

    smtPrelude :: Maybe FilePath
    smtPrelude = prelude smtOptions
