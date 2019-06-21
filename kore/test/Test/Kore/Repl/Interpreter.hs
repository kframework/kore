module Test.Kore.Repl.Interpreter
    ( test_replInterpreter
    ) where

import Test.Tasty
       ( TestTree )
import Test.Tasty.HUnit
       ( Assertion, testCase, (@?=) )

import           Control.Applicative
import           Control.Concurrent.MVar
import           Control.Monad.Reader
                 ( runReaderT )
import           Control.Monad.Trans.State.Strict
                 ( evalStateT, runStateT )
import           Data.Coerce
                 ( coerce )
import           Data.Default
                 ( def )
import           Data.IORef
                 ( newIORef, readIORef, writeIORef )
import           Data.List.NonEmpty
                 ( NonEmpty (..) )
import qualified Data.Map as Map
import qualified Data.Sequence as Seq
import           Data.Text
                 ( pack )
import qualified Data.Text.Prettyprint.Doc as Pretty

import qualified Data.Map.Strict as StrictMap
import qualified Kore.Attribute.Axiom as Attribute
import qualified Kore.Attribute.Label as AttrLabel
import qualified Kore.Builtin.Int as Int
import           Kore.Internal.Predicate
                 ( Predicate )
import qualified Kore.Internal.Predicate as Predicate
import           Kore.Internal.TermLike
                 ( TermLike, mkBottom_, mkVar, varS )
import qualified Kore.Logger.Output as Logger
import           Kore.OnePath.Verification
                 ( Axiom (..), verifyClaimStep )
import qualified Kore.Predicate.Predicate as Predicate
import           Kore.Repl.Data
import           Kore.Repl.Interpreter
import           Kore.Repl.State
import           Kore.Step.Rule
                 ( OnePathRule (..), RewriteRule (..), RulePattern (..),
                 rulePattern )

import           Kore.Step.Simplification.AndTerms
                 ( cannotUnifyDistinctDomainValues )
import           Kore.Step.Simplification.Data
                 ( Simplifier, evalSimplifier )
import           Kore.Syntax.Variable
                 ( Variable )
import           Kore.Unification.Procedure
                 ( unificationProcedure )
import           Kore.Unification.Unify
                 ( explainBottom )
import qualified SMT

import Test.Kore
import Test.Kore.Builtin.Builtin
import Test.Kore.Builtin.Definition

type Claim = OnePathRule Variable

test_replInterpreter :: [TestTree]
test_replInterpreter =
    [ showUsage                   `tests` "Showing the usage message"
    , help                        `tests` "Showing the help message"
    , step5                       `tests` "Performing 5 steps"
    , step100                     `tests` "Stepping over proof completion"
    , makeSimpleAlias             `tests` "Creating an alias with no arguments"
    , trySimpleAlias              `tests` "Executing an existing alias with no arguments"
    , makeAlias                   `tests` "Creating an alias with arguments"
    , aliasOfExistingCommand      `tests` "Create alias of existing command"
    , aliasOfUnknownCommand       `tests` "Create alias of unknown command"
    , recursiveAlias              `tests` "Create alias of unknown command"
    , tryAlias                    `tests` "Executing an existing alias with arguments"
    , unificationFailure          `tests` "Try axiom that doesn't unify"
    , unificationSuccess          `tests` "Try axiom that does unify"
    , forceFailure                `tests` "TryF axiom that doesn't unify"
    , forceSuccess                `tests` "TryF axiom that does unify"
    , proofStatus                 `tests` "Multi claim proof status"
    , logUpdatesState             `tests` "Log command updates the state"
    , showCurrentClaim            `tests` "Showing current claim"
    , showClaim1                  `tests` "Showing the claim at index 1"
    , showClaimByLabel            `tests` "Showing the claim with the label 0to10Claim"
    , showAxiomByLabel            `tests` "Showing the axiom with the label add1Axiom"
    , unificationFailureWithLabel `tests` "Try axiom by label that doesn't unify"
    , unificationSuccessWithLabel `tests` "Try axiom by label that does unify"
    , forceFailureWithLabel       `tests` "TryF axiom by label that doesn't unify"
    , forceSuccessWithLabel       `tests` "TryF axiom by label that does unify"
    , proveSecondClaim            `tests` "Starting to prove the second claim"
    , proveSecondClaimByLabel     `tests` "Starting to prove the second claim\
                                           \ referenced by label"
    ]

showUsage :: IO ()
showUsage =
    let
        axioms  = []
        claim   = emptyClaim
        command = ShowUsage
    in do
        Result { output, continue } <- run command axioms [claim] claim
        output   `equalsOutput` showUsageMessage
        continue `equals`       Continue

help :: IO ()
help =
    let
        axioms  = []
        claim   = emptyClaim
        command = Help
    in do
        Result { output, continue } <- run command axioms [claim] claim
        output   `equalsOutput` helpText
        continue `equals`       Continue

step5 :: IO ()
step5 =
    let
        axioms = [ add1 ]
        claim  = zeroToTen
        command = ProveSteps 5
    in do
        Result { output, continue, state } <- run command axioms [claim] claim
        output     `equalsOutput`   ""
        continue   `equals`         Continue
        state      `hasCurrentNode` ReplNode 5

step100 :: IO ()
step100 =
    let
        axioms = [ add1 ]
        claim  = zeroToTen
        command = ProveSteps 100
    in do
        Result { output, continue, state } <- run command axioms [claim] claim
        output     `equalsOutput`   showStepStoppedMessage 10 NoResult
        continue   `equals`         Continue
        state      `hasCurrentNode` ReplNode 10

makeSimpleAlias :: IO ()
makeSimpleAlias =
    let
        axioms  = []
        claim   = emptyClaim
        alias   = AliasDefinition { name = "a", arguments = [], command = "help" }
        command = Alias alias
    in do
        Result { output, continue, state } <- run command axioms [claim] claim
        output   `equalsOutput` ""
        continue `equals`       Continue
        state    `hasAlias`     alias

trySimpleAlias :: IO ()
trySimpleAlias =
    let
        axioms  = []
        claim   = emptyClaim
        name    = "h"
        alias   = AliasDefinition { name, arguments = [], command = "help" }
        stateT  = \st -> st { aliases = Map.insert name alias (aliases st) }
        command = TryAlias $ ReplAlias "h" []
    in do
        Result { output, continue } <-
            runWithState command axioms [claim] claim stateT
        output   `equalsOutput` helpText
        continue `equals` Continue

makeAlias :: IO ()
makeAlias =
    let
        axioms  = []
        claim   = emptyClaim
        alias   = AliasDefinition
                    { name = "c"
                    , arguments = ["n"]
                    , command = "claim n"
                    }
        command = Alias alias
    in do
        Result { output, continue, state } <- run command axioms [claim] claim
        output   `equalsOutput` ""
        continue `equals`       Continue
        state    `hasAlias`     alias

aliasOfExistingCommand :: IO ()
aliasOfExistingCommand =
    let
        axioms  = []
        claim   = emptyClaim
        alias   = AliasDefinition
                    { name = "help"
                    , arguments = ["n"]
                    , command = "claim n"
                    }
        command = Alias alias
    in do
        Result { output, continue } <- run command axioms [claim] claim
        output   `equalsOutput` showAliasError NameAlreadyDefined
        continue `equals`       Continue

aliasOfUnknownCommand :: IO ()
aliasOfUnknownCommand =
    let
        axioms  = []
        claim   = emptyClaim
        alias   = AliasDefinition
                    { name = "c"
                    , arguments = ["n"]
                    , command = "unknown n"
                    }
        command = Alias alias
    in do
        Result { output, continue } <- run command axioms [claim] claim
        output   `equalsOutput` showAliasError UnknownCommand
        continue `equals`       Continue

recursiveAlias :: IO ()
recursiveAlias =
    let
        axioms  = []
        claim   = emptyClaim
        alias   = AliasDefinition
                    { name = "c"
                    , arguments = ["n"]
                    , command = "c n"
                    }
        command = Alias alias
    in do
        Result { output, continue } <- run command axioms [claim] claim
        output   `equalsOutput` showAliasError UnknownCommand
        continue `equals`       Continue

tryAlias :: IO ()
tryAlias =
    let
        axioms  = []
        claim   = emptyClaim
        name    = "c"
        alias   = AliasDefinition
                    { name = "c"
                    , arguments = ["n"]
                    , command = "claim n"
                    }
        stateT  = \st -> st { aliases = Map.insert name alias (aliases st) }
        command = TryAlias $ ReplAlias "c" [SimpleArgument "0"]
    in do
        Result { output, continue } <-
            runWithState command axioms [claim] claim stateT
        output   `equalsOutput` showRewriteRule claim
        continue `equals` Continue

unificationFailure :: IO ()
unificationFailure =
    let
        zero = Int.asInternal intSort 0
        one = Int.asInternal intSort 1
        impossibleAxiom = coerce $ rulePattern one one
        axioms = [ impossibleAxiom ]
        claim = zeroToTen
        command = Try . ByIndex . Left $ AxiomIndex 0
    in do
        Result { output, continue, state } <- run command axioms [claim] claim
        expectedOutput <-
            formatUnificationError cannotUnifyDistinctDomainValues one zero
        output `equalsOutput` expectedOutput
        continue `equals` Continue
        state `hasCurrentNode` ReplNode 0

unificationFailureWithLabel :: IO ()
unificationFailureWithLabel =
    let
        zero = Int.asInternal intSort 0
        one = Int.asInternal intSort 1
        impossibleAxiom = coerce $ rulePatternWithLabel one one "impossible"
        axioms = [ impossibleAxiom ]
        claim = zeroToTen
        command = Try . ByLabel . RuleLabel $ "impossible"
    in do
        Result { output, continue, state } <- run command axioms [claim] claim
        expectedOutput <-
            formatUnificationError cannotUnifyDistinctDomainValues one zero
        output `equalsOutput` expectedOutput
        continue `equals` Continue
        state `hasCurrentNode` ReplNode 0

unificationSuccess :: IO ()
unificationSuccess = do
    let
        zero = Int.asInternal intSort 0
        one = Int.asInternal intSort 1
        axiom = coerce $ rulePattern zero one
        axioms = [ axiom ]
        claim = zeroToTen
        command = Try . ByIndex . Left $ AxiomIndex 0
        expectedOutput = formatUnifiers (Predicate.top :| [])

    Result { output, continue, state } <- run command axioms [claim] claim
    output `equalsOutput` expectedOutput
    continue `equals` Continue
    state `hasCurrentNode` ReplNode 0

unificationSuccessWithLabel :: IO ()
unificationSuccessWithLabel = do
    let
        zero = Int.asInternal intSort 0
        one = Int.asInternal intSort 1
        axiom = coerce $ rulePatternWithLabel zero one "0to1"
        axioms = [ axiom ]
        claim = zeroToTen
        command = Try . ByLabel . RuleLabel $ "0to1"
        expectedOutput = formatUnifiers (Predicate.top :| [])

    Result { output, continue, state } <- run command axioms [claim] claim
    output `equalsOutput` expectedOutput
    continue `equals` Continue
    state `hasCurrentNode` ReplNode 0

forceFailure :: IO ()
forceFailure =
    let
        zero = Int.asInternal intSort 0
        one = Int.asInternal intSort 1
        impossibleAxiom = coerce $ rulePattern one one
        axioms = [ impossibleAxiom ]
        claim = zeroToTen
        command = TryF . ByIndex . Left $ AxiomIndex 0
    in do
        Result { output, continue, state } <- run command axioms [claim] claim
        expectedOutput <-
            formatUnificationError cannotUnifyDistinctDomainValues one zero
        output `equalsOutput` expectedOutput
        continue `equals` Continue
        state `hasCurrentNode` ReplNode 0

forceFailureWithLabel :: IO ()
forceFailureWithLabel =
    let
        zero = Int.asInternal intSort 0
        one = Int.asInternal intSort 1
        impossibleAxiom = coerce $ rulePatternWithLabel one one "impossible"
        axioms = [ impossibleAxiom ]
        claim = zeroToTen
        command = TryF . ByLabel . RuleLabel $ "impossible"
    in do
        Result { output, continue, state } <- run command axioms [claim] claim
        expectedOutput <-
            formatUnificationError cannotUnifyDistinctDomainValues one zero
        output `equalsOutput` expectedOutput
        continue `equals` Continue
        state `hasCurrentNode` ReplNode 0

forceSuccess :: IO ()
forceSuccess = do
    let
        zero = Int.asInternal intSort 0
        one = Int.asInternal intSort 1
        axiom = coerce $ rulePattern zero one
        axioms = [ axiom ]
        claim = zeroToTen
        command = TryF . ByIndex . Left $ AxiomIndex 0
        expectedOutput = ""

    Result { output, continue, state } <- run command axioms [claim] claim
    output `equalsOutput` expectedOutput
    continue `equals` Continue
    state `hasCurrentNode` ReplNode 1

forceSuccessWithLabel :: IO ()
forceSuccessWithLabel = do
    let
        zero = Int.asInternal intSort 0
        one = Int.asInternal intSort 1
        axiom = coerce $ rulePatternWithLabel zero one "0to1"
        axioms = [ axiom ]
        claim = zeroToTen
        command = TryF . ByLabel . RuleLabel $ "0to1"
        expectedOutput = ""

    Result { output, continue, state } <- run command axioms [claim] claim
    output `equalsOutput` expectedOutput
    continue `equals` Continue
    state `hasCurrentNode` ReplNode 1

proofStatus :: IO ()
proofStatus =
    let
        claims = [zeroToTen, emptyClaim]
        claim = zeroToTen
        axioms = [add1]
        command = ProofStatus
        expectedProofStatus =
            StrictMap.fromList
                [ (ClaimIndex 0, InProgress [0])
                , (ClaimIndex 1, NotStarted)
                ]
    in do
        Result { output, continue } <-
            run command axioms claims claim
        output `equalsOutput` showProofStatus expectedProofStatus
        continue `equals` Continue

showCurrentClaim :: IO ()
showCurrentClaim =
    let
        claims = [zeroToTen, emptyClaim]
        claim = zeroToTen
        axioms = []
        command = ShowClaim Nothing
        expectedCindex = ClaimIndex 0
    in do
        Result { output, continue } <-
            run command axioms claims claim
        output `equalsOutput` showCurrentClaimIndex expectedCindex
        continue `equals` Continue

showClaim1 :: IO ()
showClaim1 =
    let
        claims = [zeroToTen, emptyClaim]
        claim = zeroToTen
        axioms = []
        command = ShowClaim (Just . Left . ClaimIndex $ 1)
        expectedClaim = emptyClaim
    in do
        Result { output, continue } <-
            run command axioms claims claim
        output `equalsOutput` showRewriteRule expectedClaim
        continue `equals` Continue

showClaimByLabel :: IO ()
showClaimByLabel =
    let
        claims = [zeroToTen, emptyClaim]
        claim = zeroToTen
        axioms = []
        command = ShowClaim (Just . Right . RuleLabel $ "0to10Claim")
        expectedClaim = zeroToTen
    in do
        Result { output, continue } <-
            run command axioms claims claim
        output `equalsOutput` showRewriteRule expectedClaim
        continue `equals` Continue

showAxiomByLabel :: IO ()
showAxiomByLabel =
    let
        claims = [zeroToTen, emptyClaim]
        claim = zeroToTen
        axioms = [add1]
        command = ShowAxiom (Right . RuleLabel $ "add1Axiom")
        expectedAxiom = add1
    in do
        Result { output, continue } <-
            run command axioms claims claim
        output `equalsOutput` showRewriteRule expectedAxiom
        continue `equals` Continue

logUpdatesState :: IO ()
logUpdatesState =
    let
        axioms  = []
        claim   = emptyClaim
        command = Log Logger.Info LogToStdOut
    in do
        Result { output, continue, state } <- run command axioms [claim] claim
        output   `equalsOutput`  ""
        continue `equals`     Continue
        state    `hasLogging` (Logger.Info, LogToStdOut)

proveSecondClaim :: IO ()
proveSecondClaim =
    let
        claims = [zeroToTen, emptyClaim]
        claim = zeroToTen
        axioms = [add1]
        indexOrLabel = Left . ClaimIndex $ 1
        command = Prove indexOrLabel
        expectedClaimIndex = ClaimIndex 1
    in do
        Result { output, continue, state } <-
            run command axioms claims claim
        output `equalsOutput` showClaimSwitch indexOrLabel
        state `hasCurrentClaimIndex` expectedClaimIndex
        continue `equals` Continue

proveSecondClaimByLabel :: IO ()
proveSecondClaimByLabel =
    let
        claims = [zeroToTen, emptyClaim]
        claim = zeroToTen
        axioms = [add1]
        indexOrLabel = Right . RuleLabel $ "emptyClaim"
        command = Prove indexOrLabel
        expectedClaimIndex = ClaimIndex 1
    in do
        Result { output, continue, state } <-
            run command axioms claims claim
        output `equalsOutput` showClaimSwitch indexOrLabel
        state `hasCurrentClaimIndex` expectedClaimIndex
        continue `equals` Continue

add1 :: Axiom
add1 =
    coerce $ rulePatternWithLabel n plusOne "add1Axiom"
  where
    one     = Int.asInternal intSort 1
    n       = mkVar $ varS "x" intSort
    plusOne = n `addInt` one

zeroToTen :: Claim
zeroToTen =
    coerce $ rulePatternWithLabel zero ten "0to10Claim"
  where
    zero = Int.asInternal intSort 0
    ten  = Int.asInternal intSort 10

emptyClaim :: Claim
emptyClaim =
    coerce
    $ rulePatternWithLabel mkBottom_ mkBottom_ "emptyClaim"

rulePatternWithLabel
    :: TermLike variable
    -> TermLike variable
    -> String
    -> RulePattern variable
rulePatternWithLabel left right label =
    RulePattern
        { left
        , right
        , requires = Predicate.makeTruePredicate
        , ensures  = Predicate.makeTruePredicate
        , attributes =
            Attribute.Axiom
                { heatCool = def
                , productionID = def
                , assoc = def
                , comm = def
                , unit = def
                , idem = def
                , trusted = def
                , concrete = def
                , simplification = def
                , overload = def
                , smtLemma = def
                , label =
                    AttrLabel.Label . return . pack $ label
                , sourceLocation = def
                , constructor = def
                , identifier = def
                }
        }


run :: ReplCommand -> [Axiom] -> [Claim] -> Claim -> IO Result
run command axioms claims claim =
    runWithState command axioms claims claim id

runSimplifier
    :: Simplifier a
    -> IO a
runSimplifier =
    SMT.runSMT SMT.defaultConfig emptyLogger . evalSimplifier testEnv

runWithState
    :: ReplCommand
    -> [Axiom]
    -> [Claim]
    -> Claim
    -> (ReplState Claim -> ReplState Claim)
    -> IO Result
runWithState command axioms claims claim stateTransformer
  = Logger.withLogger logOptions $ \logger -> do
        output <- newIORef ""
        mvar <- newMVar logger
        let state = stateTransformer $ mkState axioms claims claim
        let config = mkConfig mvar
        (c, s) <-
            liftSimplifier (Logger.swappableLogger mvar)
            $ flip runStateT state
            $ flip runReaderT config
            $ replInterpreter (writeIORefIfNotEmpty output) command
        output' <- readIORef output
        return $ Result output' c s
  where
    logOptions = Logger.KoreLogOptions Logger.LogNone Logger.Debug
    liftSimplifier logger =
        SMT.runSMT SMT.defaultConfig logger . evalSimplifier testEnv
    writeIORefIfNotEmpty out =
        \case
            "" -> pure ()
            xs -> writeIORef out xs

data Result = Result
    { output   :: String
    , continue :: ReplStatus
    , state    :: ReplState Claim
    }

equals :: (Eq a, Show a) => a -> a -> Assertion
equals = (@?=)

equalsOutput :: String -> String -> Assertion
equalsOutput "" expected     = "" @?= expected
equalsOutput actual expected = actual @?= expected <> "\n"

hasCurrentNode :: ReplState Claim -> ReplNode -> IO ()
hasCurrentNode st n = do
    node st `equals` n
    graphNode <- evalStateT (getTargetNode justNode) st
    graphNode `equals` justNode
  where
    justNode = Just n

hasAlias :: ReplState Claim -> AliasDefinition -> IO ()
hasAlias st alias@AliasDefinition { name } =
    let
        aliasMap = aliases st
        actual   = name `Map.lookup` aliasMap
    in
        actual `equals` Just alias

hasLogging :: ReplState Claim -> (Logger.Severity, LogType) -> IO ()
hasLogging st expectedLogging =
    let
        actualLogging = logging st
    in
        actualLogging `equals` expectedLogging

hasCurrentClaimIndex :: ReplState Claim -> ClaimIndex -> IO ()
hasCurrentClaimIndex st expectedClaimIndex =
    let
        actualClaimIndex = claimIndex st
    in
        actualClaimIndex `equals` expectedClaimIndex

tests :: IO () -> String -> TestTree
tests = flip testCase

mkState
    :: [Axiom]
    -> [Claim]
    -> Claim
    -> ReplState Claim
mkState axioms claims claim =
    ReplState
        { axioms      = axioms
        , claims      = claims
        , claim       = claim
        , claimIndex  = ClaimIndex 0
        , graphs      = Map.singleton (ClaimIndex 0) graph'
        , node        = ReplNode 0
        , commands    = Seq.empty
        , omit        = []
        , labels      = Map.singleton (ClaimIndex 0) Map.empty
        , aliases     = Map.empty
        , logging     = (Logger.Debug, NoLogging)
        }
  where
    graph' = emptyExecutionGraph claim

mkConfig :: MVar (Logger.LogAction IO Logger.LogMessage) -> Config Claim Simplifier
mkConfig logger =
    Config
        { stepper     = stepper0
        , unifier     = unificationProcedure
        , logger
        , outputFile  = OutputFile Nothing
        }
  where
    stepper0 claim' claims' axioms' graph (ReplNode node) =
        verifyClaimStep claim' claims' axioms' graph node

formatUnificationError
    :: Pretty.Doc ()
    -> TermLike Variable
    -> TermLike Variable
    -> IO String
formatUnificationError info first second = do
    res <- runSimplifier . runUnifierWithExplanation $ do
        explainBottom info first second
        empty
    return $ formatUnificationMessage res

formatUnifiers :: NonEmpty (Predicate Variable) -> String
formatUnifiers = formatUnificationMessage . Right
