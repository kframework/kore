module Main (main) where

import Prelude.Kore

import qualified Control.Lens as Lens
import Control.Monad.Catch
    ( MonadMask
    , SomeException
    , fromException
    , handle
    , throwM
    )
import Control.Monad.Extra as Monad
import Data.Default
    ( def
    )
import Data.Generics.Product
    ( field
    )
import Data.Limit
    ( Limit (..)
    , maybeLimit
    )
import Data.List
    ( intercalate
    )
import Data.Reflection
import Data.Text
    ( Text
    , unpack
    )
import qualified Data.Text as Text
    ( null
    , split
    )
import qualified Data.Text.IO as Text
    ( putStrLn
    , readFile
    )
import qualified GHC.Generics as GHC
import Options.Applicative
    ( InfoMod
    , Parser
    , argument
    , auto
    , fullDesc
    , header
    , help
    , long
    , metavar
    , option
    , progDesc
    , readerError
    , str
    , strOption
    , value
    )
import qualified Options.Applicative as Options
import System.Clock
    ( Clock (Monotonic)
    , TimeSpec
    , getTime
    )
import System.Directory
    ( copyFile
    , doesFileExist
    , emptyPermissions
    , setOwnerExecutable
    , setOwnerReadable
    , setOwnerSearchable
    , setOwnerWritable
    , setPermissions
    )
import System.Exit
    ( exitWith
    )
import System.FilePath
    ( (</>)
    )
import System.IO
    ( IOMode (WriteMode)
    , withFile
    )

import qualified Data.Limit as Limit
import Kore.Attribute.Symbol as Attribute
import Kore.BugReport
import Kore.Exec
import Kore.IndexedModule.IndexedModule
    ( VerifiedModule
    , indexedModuleRawSentences
    )
import qualified Kore.IndexedModule.MetadataToolsBuilder as MetadataTools
    ( build
    )
import Kore.Internal.MultiAnd
    ( MultiAnd
    )
import qualified Kore.Internal.MultiAnd as MultiAnd
import qualified Kore.Internal.OrPattern as OrPattern
import Kore.Internal.Pattern
    ( Conditional (..)
    , Pattern
    )
import Kore.Internal.Predicate
    ( makePredicate
    )
import Kore.Internal.TermLike
    ( pattern And_
    , TermLike
    , VariableName
    , mkElemVar
    , mkElementVariable
    , mkSort
    , mkSortVariable
    , mkTop
    , noLocationId
    )
import Kore.Log
    ( KoreLogOptions (..)
    , LogMessage
    , SomeEntry (..)
    , WithLog
    , logEntry
    , parseKoreLogOptions
    , runKoreLog
    , unparseKoreLogOptions
    )
import Kore.Log.ErrorException
    ( errorException
    )
import Kore.Log.WarnIfLowProductivity
    ( warnIfLowProductivity
    )
import qualified Kore.ModelChecker.Bounded as Bounded
    ( CheckResult (..)
    )
import Kore.Parser
    ( ParsedPattern
    , parseKorePattern
    )
import Kore.Reachability
    ( ProveClaimsResult (..)
    , SomeClaim
    , StuckClaim (..)
    , getConfiguration
    )
import qualified Kore.Reachability.Claim as Claim
import Kore.Rewriting.RewritingVariable
import Kore.Step
import Kore.Step.RulePattern
    ( RewriteRule
    )
import Kore.Step.Search
    ( SearchType (..)
    )
import qualified Kore.Step.Search as Search
import Kore.Step.SMT.Lemma
import Kore.Step.Strategy
    ( GraphSearchOrder (..)
    )
import Kore.Syntax.Definition
    ( Definition (Definition)
    , Module (Module)
    , ModuleName (..)
    , Sentence (..)
    )
import qualified Kore.Syntax.Definition as Definition.DoNotUse
import Kore.TopBottom
    ( isTop
    )
import Kore.Unparser
    ( unparse
    )
import Options.SMT
    ( KoreSolverOptions (..)
    , Solver (..)
    , ensureSmtPreludeExists
    , parseKoreSolverOptions
    , unparseKoreSolverOptions
    , writeKoreSolverFiles
    )
import Pretty
    ( Doc
    , Pretty (..)
    , hPutDoc
    , putDoc
    , vsep
    )
import Prof
    ( MonadProf
    )
import SMT
    ( MonadSMT
    )
import qualified SMT
import Stats

import GlobalMain

{-
Main module to run kore-exec
TODO: add command line argument tab-completion
-}

data KoreSearchOptions =
    KoreSearchOptions
        { searchFileName :: !FilePath
        -- ^ Name of file containing a pattern to match during execution
        , bound :: !(Limit Natural)
        -- ^ The maximum bound on the number of search matches
        , searchType :: !SearchType
        -- ^ The type of search to perform
        } deriving (GHC.Generic)

parseKoreSearchOptions :: Parser KoreSearchOptions
parseKoreSearchOptions =
    KoreSearchOptions
    <$> strOption
        (  metavar "SEARCH_FILE"
        <> long "search"
        <> help "Kore source file representing pattern to search for. \
                \Needs --module."
        )
    <*> parseBound
    <*> parseSearchType
  where
    parseBound = Limit <$> bound <|> pure Unlimited
    bound =
        option auto
            (  metavar "BOUND"
            <> long "bound"
            <> help "Maximum number of solutions."
            )
    parseSearchType =
        parseSum
            "SEARCH_TYPE"
            "searchType"
            "Search type (selects potential solutions)"
            (map (\s -> (show s, s)) [ ONE, FINAL, STAR, PLUS ])

parseSum :: String -> String -> String -> [(String, value)] -> Parser value
parseSum metaName longName helpMsg options =
    option (snd <$> readSum longName options)
        (  metavar metaName
        <> long longName
        <> help (helpMsg <> ": " <> knownOptions)
        )
  where
    knownOptions = intercalate ", " (map fst options)

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

applyKoreSearchOptions
    :: Maybe KoreSearchOptions
    -> KoreExecOptions
    -> KoreExecOptions
applyKoreSearchOptions Nothing koreExecOpts = koreExecOpts
applyKoreSearchOptions koreSearchOptions@(Just koreSearchOpts) koreExecOpts =
    koreExecOpts
        { koreSearchOptions
        , strategy =
            -- Search relies on exploring the entire space of states.
            ("all", priorityAllStrategy)
        , depthLimit = min depthLimit searchTypeDepthLimit
        }
  where
    KoreSearchOptions { searchType } = koreSearchOpts
    KoreExecOptions { depthLimit } = koreExecOpts
    searchTypeDepthLimit =
        case searchType of
            ONE -> Limit 1
            _ -> Unlimited

-- | Main options record
data KoreExecOptions = KoreExecOptions
    { definitionFileName  :: !FilePath
    -- ^ Name for a file containing a definition to verify and use for execution
    , patternFileName     :: !(Maybe FilePath)
    -- ^ Name for file containing a pattern to verify and use for execution
    , outputFileName      :: !(Maybe FilePath)
    -- ^ Name for file to contain the output pattern
    , mainModuleName      :: !ModuleName
    -- ^ The name of the main module in the definition
    , breadthLimit        :: !(Limit Natural)
    , depthLimit          :: !(Limit Natural)
    , strategy            :: !(String, [RewriteRule RewritingVariableName] -> Strategy (Prim (RewriteRule RewritingVariableName)))
    , koreSolverOptions   :: !KoreSolverOptions
    , koreLogOptions      :: !KoreLogOptions
    , koreSearchOptions   :: !(Maybe KoreSearchOptions)
    , koreProveOptions    :: !(Maybe KoreProveOptions)
    , koreMergeOptions    :: !(Maybe KoreMergeOptions)
    , rtsStatistics       :: !(Maybe FilePath)
    , bugReport           :: !BugReport
    } deriving (GHC.Generic)

-- | Command Line Argument Parser
parseKoreExecOptions :: TimeSpec -> Parser KoreExecOptions
parseKoreExecOptions startTime =
    applyKoreSearchOptions
        <$> optional parseKoreSearchOptions
        <*> parseKoreExecOptions0
  where
    parseKoreExecOptions0 :: Parser KoreExecOptions
    parseKoreExecOptions0 =
        KoreExecOptions
        <$> argument str
            (  metavar "DEFINITION_FILE"
            <> help "Kore definition file to verify and use for execution" )
        <*> optional
            (strOption
                (  metavar "PATTERN_FILE"
                <> long "pattern"
                <> help
                    "Verify and execute the Kore pattern found in PATTERN_FILE."
                )
            )
        <*> optional
            (strOption
                (  metavar "PATTERN_OUTPUT_FILE"
                <> long "output"
                <> help "Output file to contain final Kore pattern."
                )
            )
        <*> parseMainModuleName
        <*> parseBreadthLimit
        <*> parseDepthLimit
        <*> parseStrategy
        <*> parseKoreSolverOptions
        <*> parseKoreLogOptions (ExeName "kore-exec") startTime
        <*> pure Nothing
        <*> optional parseKoreProveOptions
        <*> optional parseKoreMergeOptions
        <*> optional parseRtsStatistics
        <*> parseBugReport

    parseBreadthLimit = Limit <$> breadth <|> pure Unlimited
    parseDepthLimit = Limit <$> depth <|> pure Unlimited
    parseStrategy =
        option (readSum "strategy" strategies)
            (  metavar "STRATEGY"
            <> long "strategy"
            <> value ("all", priorityAllStrategy)
            <> help "Select rewrites using STRATEGY."
            )
      where
        strategies =
            [ ("any", priorityAnyStrategy)
            , ("all", priorityAllStrategy)
            ]

    breadth =
        option auto
            (  metavar "BREADTH"
            <> long "breadth"
            <> help "Allow up to BREADTH parallel execution branches."
            )
    depth =
        option auto
            (  metavar "DEPTH"
            <> long "depth"
            <> help "Execute up to DEPTH steps."
            )

    parseMainModuleName =
        GlobalMain.parseModuleName
            "MODULE"
            "module"
            "The name of the main module in the Kore definition."
    parseRtsStatistics =
        strOption (mconcat infos)
      where
        infos =
            [ metavar "FILENAME"
            , long "rts-statistics"
            , help "Write runtime statistics to FILENAME in JSON format."
            ]

-- | modifiers for the Command line parser description
parserInfoModifiers :: InfoMod options
parserInfoModifiers =
    fullDesc
    <> progDesc "Uses Kore definition in DEFINITION_FILE to execute pattern \
                \in PATTERN_FILE."
    <> header "kore-exec - an interpreter for Kore definitions"

unparseKoreSearchOptions :: KoreSearchOptions -> [String]
unparseKoreSearchOptions (KoreSearchOptions _ bound searchType) =
    [ "--search searchFile.kore"
    , maybeLimit "" (\limit -> "--bound " <> show limit) bound
    , "--searchType " <> show searchType
    ]

unparseKoreMergeOptions :: KoreMergeOptions -> [String]
unparseKoreMergeOptions (KoreMergeOptions _ maybeBatchSize) =
    [ "--merge-rules mergeRules.kore"]
    <> maybe mempty ((:[]) . ("--merge-batch-size " <>) . show) maybeBatchSize

unparseKoreProveOptions :: KoreProveOptions -> [String]
unparseKoreProveOptions
    ( KoreProveOptions
        _
        (ModuleName moduleName)
        graphSearch
        bmc
        saveProofs
    )
  =
    [ "--prove spec.kore"
    , "--spec-module " <> unpack moduleName
    , "--graph-search "
        <> if graphSearch == DepthFirst then "depth-first" else "breadth-first"
    , if bmc then "--bmc" else ""
    , maybe "" ("--save-proofs " <>) saveProofs
    ]

koreExecSh :: KoreExecOptions -> String
koreExecSh
    koreExecOptions@( KoreExecOptions
        _
        patternFileName
        outputFileName
        mainModuleName
        breadthLimit
        depthLimit
        strategy
        koreSolverOptions
        koreLogOptions
        koreSearchOptions
        koreProveOptions
        koreMergeOptions
        rtsStatistics
        _
    )
  =
    unlines $
        [ "#!/bin/sh"
        , "exec kore-exec \\"
        ]
        <> fmap (\line -> "    " <> line <> " \\") options
        <> ["    \"$@\""]
  where
    options =
        concat
        [ catMaybes
            [ pure $ defaultDefinitionFilePath koreExecOptions
            , patternFileName $> "--pattern pgm.kore"
            , outputFileName $> "--output result.kore"
            , pure $ "--module " <> unpack (getModuleName mainModuleName)
            , (\limit -> unwords ["--breadth", show limit])
                <$> maybeLimit Nothing Just breadthLimit
            , (\limit -> unwords ["--depth", show limit])
                <$> maybeLimit Nothing Just depthLimit
            , pure $ "--strategy " <> fst strategy
            , rtsStatistics $>
                unwords ["--rts-statistics", defaultRtsStatisticsFilePath]
            ]
        , unparseKoreSolverOptions koreSolverOptions
        , unparseKoreLogOptions koreLogOptions
        , maybe mempty unparseKoreSearchOptions koreSearchOptions
        , maybe mempty unparseKoreProveOptions koreProveOptions
        , maybe mempty unparseKoreMergeOptions koreMergeOptions
        ]

defaultDefinitionFilePath :: KoreExecOptions -> FilePath
defaultDefinitionFilePath KoreExecOptions { koreProveOptions }
  | isJust koreProveOptions = "vdefinition.kore"
  | otherwise               = "definition.kore"

defaultRtsStatisticsFilePath :: FilePath
defaultRtsStatisticsFilePath = "rts-statistics.json"

writeKoreSearchFiles :: FilePath -> KoreSearchOptions -> IO ()
writeKoreSearchFiles reportFile KoreSearchOptions { searchFileName } =
    copyFile searchFileName $ reportFile <> "/searchFile.kore"

writeKoreMergeFiles :: FilePath -> KoreMergeOptions -> IO ()
writeKoreMergeFiles reportFile KoreMergeOptions { rulesFileName } =
    copyFile rulesFileName $ reportFile <> "/mergeRules.kore"

writeKoreProveFiles :: FilePath -> KoreProveOptions -> IO ()
writeKoreProveFiles reportFile koreProveOptions = do
    let KoreProveOptions { specFileName } = koreProveOptions
    copyFile specFileName (reportFile </> "spec.kore")
    let KoreProveOptions { saveProofs } = koreProveOptions
    for_ saveProofs $ \filePath ->
        Monad.whenM
            (doesFileExist filePath)
            (copyFile filePath (reportFile </> "save-proofs.kore"))

writeOptionsAndKoreFiles :: FilePath -> KoreExecOptions -> IO ()
writeOptionsAndKoreFiles
    reportDirectory
    opts@KoreExecOptions
        { definitionFileName
        , patternFileName
        , koreSolverOptions
        , koreSearchOptions
        , koreProveOptions
        , koreMergeOptions
        }
  = do
    let shellScript = reportDirectory </> "kore-exec.sh"
    writeFile shellScript . koreExecSh $ opts
    let allPermissions =
            setOwnerReadable True
            . setOwnerWritable True
            . setOwnerExecutable True
            . setOwnerSearchable True
    setPermissions shellScript $ allPermissions emptyPermissions
    copyFile definitionFileName
        (reportDirectory </> defaultDefinitionFilePath opts)
    for_ patternFileName
        $ flip copyFile (reportDirectory </> "pgm.kore")
    writeKoreSolverFiles koreSolverOptions reportDirectory
    for_ koreSearchOptions
        (writeKoreSearchFiles reportDirectory)
    for_ koreMergeOptions
        (writeKoreMergeFiles reportDirectory)
    for_ koreProveOptions
        (writeKoreProveFiles reportDirectory)

exeName :: ExeName
exeName = ExeName "kore-exec"

-- | Environment variable name for extra arguments
envName :: String
envName = "KORE_EXEC_OPTS"

-- TODO(virgil): Maybe add a regression test for main.
-- | Loads a kore definition file and uses it to execute kore programs
main :: IO ()
main = do
    startTime <- getTime Monotonic
    options <-
        mainGlobal
            Main.exeName
            (Just envName)
            (parseKoreExecOptions startTime)
            parserInfoModifiers
    for_ (localOptions options) mainWithOptions

mainWithOptions :: KoreExecOptions -> IO ()
mainWithOptions execOptions = do
    let KoreExecOptions { koreLogOptions, koreSolverOptions, bugReport } = execOptions
    ensureSmtPreludeExists koreSolverOptions
    exitCode <-
        withBugReport Main.exeName bugReport $ \tmpDir -> do
            writeOptionsAndKoreFiles tmpDir execOptions
            go <* warnIfLowProductivity
                & handle handleWithConfiguration
                & handle handleSomeException
                & runKoreLog tmpDir koreLogOptions
    let KoreExecOptions { rtsStatistics } = execOptions
    for_ rtsStatistics $ \filePath ->
        writeStats filePath =<< getStats
    exitWith exitCode
  where
    KoreExecOptions { koreProveOptions } = execOptions
    KoreExecOptions { koreSearchOptions } = execOptions
    KoreExecOptions { koreMergeOptions } = execOptions

    handleSomeException :: SomeException -> Main ExitCode
    handleSomeException someException = do
        case fromException someException of
            Just (SomeEntry entry) -> logEntry entry
            Nothing -> errorException someException
        throwM someException

    handleWithConfiguration :: Claim.WithConfiguration -> Main ExitCode
    handleWithConfiguration
        (Claim.WithConfiguration lastConfiguration someException)
      = do
        liftIO $ renderResult
            execOptions
            ("// Last configuration:\n" <> unparse lastConfiguration)
        throwM someException

    go :: Main ExitCode
    go
      | Just proveOptions@KoreProveOptions{bmc} <- koreProveOptions =
        if bmc
            then koreBmc execOptions proveOptions
            else koreProve execOptions proveOptions

      | Just searchOptions <- koreSearchOptions =
        koreSearch execOptions searchOptions

      | Just mergeOptions <- koreMergeOptions =
        koreMerge execOptions mergeOptions

      | otherwise =
        koreRun execOptions

koreSearch :: KoreExecOptions -> KoreSearchOptions -> Main ExitCode
koreSearch execOptions searchOptions = do
    let KoreExecOptions { definitionFileName } = execOptions
    definition <- loadDefinitions [definitionFileName]
    let KoreExecOptions { mainModuleName } = execOptions
    mainModule <- loadModule mainModuleName definition
    let KoreSearchOptions { searchFileName } = searchOptions
    target <- mainParseSearchPattern mainModule searchFileName
    let KoreExecOptions { patternFileName } = execOptions
    initial <- loadPattern mainModule patternFileName
    final <-
        execute execOptions mainModule
        $ search breadthLimit mainModule strategy' initial target config
    lift $ renderResult execOptions (unparse final)
    return ExitSuccess
  where
    KoreSearchOptions { bound, searchType } = searchOptions
    config = Search.Config { bound, searchType }
    KoreExecOptions { breadthLimit, depthLimit, strategy } = execOptions
    strategy' = Limit.replicate depthLimit . snd strategy

koreRun :: KoreExecOptions -> Main ExitCode
koreRun execOptions = do
    let KoreExecOptions { definitionFileName } = execOptions
    definition <- loadDefinitions [definitionFileName]
    let KoreExecOptions { mainModuleName } = execOptions
    mainModule <- loadModule mainModuleName definition
    let KoreExecOptions { patternFileName } = execOptions
    initial <- loadPattern mainModule patternFileName
    (exitCode, final) <-
        execute execOptions mainModule
        $ exec breadthLimit mainModule strategy' initial
    lift $ renderResult execOptions (unparse final)
    return exitCode
  where
    KoreExecOptions { breadthLimit, depthLimit, strategy } = execOptions
    strategy' = Limit.replicate depthLimit . snd strategy

koreProve :: KoreExecOptions -> KoreProveOptions -> Main ExitCode
koreProve execOptions proveOptions = do
    let KoreExecOptions { definitionFileName } = execOptions
        KoreProveOptions { specFileName } = proveOptions
    definition <- loadDefinitions [definitionFileName, specFileName]
    let KoreExecOptions { mainModuleName } = execOptions
    mainModule <- loadModule mainModuleName definition
    let KoreProveOptions { specMainModule } = proveOptions
    specModule <- loadModule specMainModule definition
    let KoreProveOptions { saveProofs } = proveOptions
    maybeAlreadyProvenModule <- loadProven definitionFileName saveProofs
    proveResult <- execute execOptions mainModule $ do
        let KoreExecOptions { breadthLimit, depthLimit } = execOptions
            KoreProveOptions { graphSearch } = proveOptions
        prove
            graphSearch
            breadthLimit
            depthLimit
            mainModule
            specModule
            maybeAlreadyProvenModule

    let ProveClaimsResult { stuckClaims, provenClaims } = proveResult
    let (exitCode, final)
          | noStuckClaims = success
          | otherwise =
            stuckPatterns
            & OrPattern.toTermLike
            & failure
          where
            noStuckClaims = isTop stuckClaims
            stuckPatterns =
                OrPattern.fromPatterns (MultiAnd.map getStuckConfig stuckClaims)
            getStuckConfig =
                getRewritingPattern . getConfiguration . getStuckClaim
    lift $ for_ saveProofs $ saveProven specModule provenClaims
    lift $ renderResult execOptions (unparse final)
    return exitCode
  where
    failure pat = (ExitFailure 1, pat)
    success :: (ExitCode, TermLike VariableName)
    success = (ExitSuccess, mkTop $ mkSortVariable "R")

    loadProven
        :: FilePath
        -> Maybe FilePath
        -> Main (Maybe (VerifiedModule StepperAttributes))
    loadProven _ Nothing = return Nothing
    loadProven definitionFileName (Just saveProofsFileName) = do
        fileExists <- lift $ doesFileExist saveProofsFileName
        if fileExists
            then do
                savedProofsDefinition <-
                    loadDefinitions [definitionFileName, saveProofsFileName]
                savedProofsModule <-
                    loadModule savedProofsModuleName savedProofsDefinition
                return (Just savedProofsModule)
            else return Nothing

    saveProven
        :: VerifiedModule StepperAttributes
        -> MultiAnd SomeClaim
        -> FilePath
        -> IO ()
    saveProven specModule (toList -> provenClaims) outputFile =
        withFile outputFile WriteMode
            (`hPutDoc` unparse provenDefinition)
      where
        specModuleDefinitions :: [Sentence (TermLike VariableName)]
        specModuleDefinitions =
            filter isNotAxiomOrClaim (indexedModuleRawSentences specModule)

        isNotAxiomOrClaim :: Sentence patternType -> Bool
        isNotAxiomOrClaim (SentenceAxiomSentence  _) = False
        isNotAxiomOrClaim (SentenceClaimSentence _) = False
        isNotAxiomOrClaim (SentenceAliasSentence _) = True
        isNotAxiomOrClaim (SentenceSymbolSentence _) = True
        isNotAxiomOrClaim (SentenceImportSentence _) = True
        isNotAxiomOrClaim (SentenceSortSentence _) = True
        isNotAxiomOrClaim (SentenceHookSentence _) = True

        provenClaimSentences = map (from @SomeClaim @(Sentence _)) provenClaims
        provenModule =
            Module
                { moduleName = savedProofsModuleName
                , moduleSentences =
                    specModuleDefinitions <> provenClaimSentences
                , moduleAttributes = def
                }

        provenDefinition = Definition
            { definitionAttributes = def
            , definitionModules = [provenModule]
            }

koreBmc :: KoreExecOptions -> KoreProveOptions -> Main ExitCode
koreBmc execOptions proveOptions = do
    let KoreExecOptions { definitionFileName } = execOptions
        KoreProveOptions { specFileName } = proveOptions
    definition <- loadDefinitions [definitionFileName, specFileName]
    let KoreExecOptions { mainModuleName } = execOptions
    mainModule <- loadModule mainModuleName definition
    let KoreProveOptions { specMainModule } = proveOptions
    specModule <- loadModule specMainModule definition
    (exitCode, final) <- execute execOptions mainModule $ do
        let KoreExecOptions { breadthLimit, depthLimit } = execOptions
            KoreProveOptions { graphSearch } = proveOptions
        checkResult <-
            boundedModelCheck
                breadthLimit
                depthLimit
                mainModule
                specModule
                graphSearch
        case checkResult of
            Bounded.Proved -> return success
            Bounded.Unknown -> return unknown
            Bounded.Failed final -> return (failure final)
    lift $ renderResult execOptions (unparse final)
    return exitCode
  where
    failure pat = (ExitFailure 1, pat)
    success = (ExitSuccess, mkTop $ mkSortVariable "R")
    unknown =
        ( ExitSuccess
        , mkElemVar $ mkElementVariable "Unknown" (mkSort $ noLocationId "SortUnknown")
        )

koreMerge :: KoreExecOptions -> KoreMergeOptions -> Main ExitCode
koreMerge execOptions mergeOptions = do
    let KoreExecOptions {definitionFileName} = execOptions
    definition <- loadDefinitions [definitionFileName]
    let KoreExecOptions {mainModuleName} = execOptions
    mainModule <- loadModule mainModuleName definition
    let KoreMergeOptions {rulesFileName} = mergeOptions
    ruleIds <- lift $ loadRuleIds rulesFileName
    let KoreMergeOptions {maybeBatchSize} = mergeOptions
    eitherMergedRule <- execute execOptions mainModule $
        case maybeBatchSize of
            Just batchSize ->
                mergeRulesConsecutiveBatches batchSize mainModule ruleIds
            Nothing -> mergeAllRules mainModule ruleIds
    case eitherMergedRule of
        (Left err) -> do
            lift $ Text.putStrLn err
            return (ExitFailure 1)
        (Right mergedRule) -> do
            lift $ renderResult execOptions (vsep (map unparse mergedRule))
            return ExitSuccess

loadRuleIds :: FilePath -> IO [Text]
loadRuleIds fileName = do
    fileContents <- Text.readFile fileName
    return
        (filter
            (not . Text.null)
            (Text.split (`elem` (" \t\n\r" :: String)) fileContents)
        )

type MonadExecute exe =
    ( MonadMask exe
    , MonadIO exe
    , MonadSMT exe
    , MonadProf exe
    , WithLog LogMessage exe
    )

-- | Run the worker in the context of the main module.
execute
    :: forall r
    .  KoreExecOptions
    -> LoadedModule  -- ^ Main module
    -> (forall exe. MonadExecute exe => exe r)  -- ^ Worker
    -> Main r
execute options mainModule worker =
    clockSomethingIO "Executing"
        $ case solver of
            Z3   -> withZ3
            None -> withoutSMT
  where
    withZ3 =
        SMT.runSMT
            config
            ( give
                (MetadataTools.build mainModule)
                (declareSMTLemmas mainModule)
            )
            worker
    withoutSMT = SMT.runNoSMT worker
    KoreSolverOptions { timeOut, resetInterval, prelude, solver } =
        Lens.view (field @"koreSolverOptions") options
    config =
        SMT.defaultConfig
            { SMT.timeOut = timeOut
            , SMT.resetInterval = resetInterval
            , SMT.prelude = prelude
            }

loadPattern :: LoadedModule -> Maybe FilePath -> Main (TermLike VariableName)
loadPattern mainModule (Just fileName) =
    mainPatternParseAndVerify mainModule fileName
loadPattern _ Nothing = error "Missing: --pattern PATTERN_FILE"

-- | IO action that parses a kore pattern from a filename and prints timing
-- information.
mainPatternParse :: String -> Main ParsedPattern
mainPatternParse = mainParse parseKorePattern

renderResult :: KoreExecOptions -> Doc ann -> IO ()
renderResult KoreExecOptions { outputFileName } doc =
    case outputFileName of
        Nothing -> putDoc doc
        Just outputFile -> withFile outputFile WriteMode (`hPutDoc` doc)

-- | IO action that parses a kore pattern from a filename, verifies it,
-- converts it to a pure pattern, and prints timing information.
mainPatternParseAndVerify
    :: VerifiedModule StepperAttributes
    -> String
    -> Main (TermLike VariableName)
mainPatternParseAndVerify indexedModule patternFileName =
    mainPatternParse patternFileName >>= mainPatternVerify indexedModule

mainParseSearchPattern
    :: VerifiedModule StepperAttributes
    -> String
    -> Main (Pattern VariableName)
mainParseSearchPattern indexedModule patternFileName = do
    purePattern <- mainPatternParseAndVerify indexedModule patternFileName
    case purePattern of
        And_ _ term predicateTerm -> return
            Conditional
                { term
                , predicate =
                    either (error . show . pretty) id
                        (makePredicate predicateTerm)
                , substitution = mempty
                }
        _ -> error "Unexpected non-conjunctive pattern"

savedProofsModuleName :: ModuleName
savedProofsModuleName = ModuleName
    "haskell-backend-saved-claims-43943e50-f723-47cd-99fd-07104d664c6d"
