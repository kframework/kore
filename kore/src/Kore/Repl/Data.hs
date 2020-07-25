{-|
Module      : Kore.Repl.Data
Description : REPL data structures.
Copyright   : (c) Runtime Verification, 2019
License     : NCSA
Maintainer  : vladimir.ciobanu@runtimeverification.com
-}

module Kore.Repl.Data
    ( ReplCommand (..)
    , helpText
    , ExecutionGraph
    , AxiomIndex (..), ClaimIndex (..)
    , RuleName (..), RuleReference(..)
    , ReplNode (..)
    , Claim
    , Axiom
    , ReplState (..)
    , ReplOutput (..)
    , ReplOut (..)
    , PrintAuxOutput (..)
    , PrintKoreOutput (..)
    , Config (..)
    , NodeState (..)
    , GraphProofStatus (..)
    , AliasDefinition (..), ReplAlias (..), AliasArgument(..), AliasError (..)
    , InnerGraph
    , shouldStore
    , commandSet
    , UnifierWithExplanation (..)
    , runUnifierWithExplanation
    , StepResult(..)
    , LogType (..)
    , ReplScript (..)
    , ReplMode (..)
    , ScriptModeOutput (..)
    , OutputFile (..)
    , makeAuxReplOutput, makeKoreReplOutput
    , GraphView (..)
    , GeneralLogOptions (..)
    , generalLogOptionsTransformer
    , debugAttemptEquationTransformer
    , debugApplyEquationTransformer
    , debugEquationTransformer
    , entriesForHelp
    ) where

import Prelude.Kore

import Control.Concurrent.MVar
import Control.Monad.Trans.Accum
    ( AccumT
    , runAccumT
    )
import qualified Control.Monad.Trans.Accum as Monad.Accum
import qualified Control.Monad.Trans.Class as Monad.Trans
import qualified Data.Graph.Inductive.Graph as Graph
import Data.Graph.Inductive.PatriciaTree
    ( Gr
    )
import qualified Data.GraphViz as Graph
import Data.List
    ( sort
    )
import Data.Map.Strict
    ( Map
    )
import Data.Monoid
    ( First (..)
    )
import Data.Sequence
    ( Seq
    )
import Data.Set
    ( Set
    )
import qualified Data.Set as Set
import qualified GHC.Generics as GHC
import Numeric.Natural
import qualified Pretty

import Kore.Internal.Condition
    ( Condition
    )
import Kore.Internal.SideCondition
    ( SideCondition
    )
import Kore.Internal.TermLike
    ( TermLike
    )
import Kore.Log
    ( ActualEntry (..)
    , LogAction (..)
    , MonadLog (..)
    )
import qualified Kore.Log as Log
import qualified Kore.Log.Registry as Log
import Kore.Step.Simplification.Data
    ( MonadSimplify (..)
    )
import qualified Kore.Step.Simplification.Not as Not
import qualified Kore.Step.Strategy as Strategy
import Kore.Strategies.Goal
import Kore.Strategies.Verification
    ( CommonProofState
    )
import Logic

import Kore.Syntax.Module
    ( ModuleName (..)
    )
import Kore.Syntax.Variable
import Kore.Unification.UnifierT
    ( MonadUnify
    , UnifierT (..)
    )
import qualified Kore.Unification.UnifierT as Monad.Unify
import Kore.Unparser
    ( unparse
    )
import SMT
    ( MonadSMT
    )

-- | Represents an optional file name which contains a sequence of
-- repl commands.
newtype ReplScript = ReplScript
    { unReplScript :: Maybe FilePath
    } deriving (Eq, Show)

data ReplMode = Interactive | RunScript
    deriving (Eq, Show)

data ScriptModeOutput = EnableOutput | DisableOutput
    deriving (Eq, Show)

newtype OutputFile = OutputFile
    { unOutputFile :: Maybe FilePath
    } deriving (Eq, Show)

newtype AxiomIndex = AxiomIndex
    { unAxiomIndex :: Int
    } deriving (Eq, Show)

newtype ClaimIndex = ClaimIndex
    { unClaimIndex :: Int
    } deriving (Eq, Ord, Show)

newtype ReplNode = ReplNode
    { unReplNode :: Graph.Node
    } deriving (Eq, Show)

newtype RuleName = RuleName
    { unRuleName :: String
    } deriving (Eq, Show)

-- | The repl keeps Kore output separated from any other kinds of auxiliary output.
-- This makes it possible to treat the output differently by using different
-- printing functions. For example, the pipe command will only send KoreOut to the
-- process' input handle.
newtype ReplOutput =
    ReplOutput
    { unReplOutput :: [ReplOut]
    } deriving (Eq, Show, Semigroup, Monoid)

-- | Newtypes for printing functions called by Kore.Repl.Interpreter.replInterpreter0
newtype PrintAuxOutput = PrintAuxOutput
    { unPrintAuxOutput :: String -> IO () }

newtype PrintKoreOutput = PrintKoreOutput
    { unPrintKoreOutput :: String -> IO () }

data ReplOut = AuxOut String | KoreOut String
    deriving (Eq, Show)

data AliasDefinition = AliasDefinition
    { name      :: String
    , arguments :: [String]
    , command   :: String
    } deriving (Eq, Show)

data AliasArgument
  = SimpleArgument String
  | QuotedArgument String
  deriving (Eq, Show)

data ReplAlias = ReplAlias
    { name      :: String
    , arguments :: [AliasArgument]
    } deriving (Eq, Show)

data LogType
    = NoLogging
    | LogToStdErr
    | LogToFile !FilePath
    deriving (Eq, Show)

data RuleReference
    = ByIndex (Either AxiomIndex ClaimIndex)
    | ByName RuleName
    deriving (Eq, Show)

-- | Option for viewing the full (expanded) graph
-- or the collapsed graph where only the branching nodes,
-- their direct descendents and leafs are visible
data GraphView
    = Collapsed
    | Expanded
    deriving (Eq, Show)

-- | Log options which can be changed by the log command.
data GeneralLogOptions =
    GeneralLogOptions
        { logType :: !Log.KoreLogType
        , logLevel :: !Log.Severity
        , timestampsSwitch :: !Log.TimestampsSwitch
        , logEntries :: !Log.EntryTypes
        }
    deriving (Eq, Show)

generalLogOptionsTransformer
    :: GeneralLogOptions
    -> Log.KoreLogOptions
    -> Log.KoreLogOptions
generalLogOptionsTransformer
    logOptions@(GeneralLogOptions _ _ _ _)
    koreLogOptions
  =
    koreLogOptions
        { Log.logLevel = logLevel
        , Log.logEntries = logEntries
        , Log.logType = logType
        , Log.timestampsSwitch = timestampsSwitch
        }
  where
    GeneralLogOptions
        { logLevel
        , logType
        , logEntries
        , timestampsSwitch
        } = logOptions

debugAttemptEquationTransformer
    :: Log.DebugAttemptEquationOptions
    -> Log.KoreLogOptions
    -> Log.KoreLogOptions
debugAttemptEquationTransformer
    debugAttemptEquationOptions
    koreLogOptions
  =
    koreLogOptions
        { Log.debugAttemptEquationOptions = debugAttemptEquationOptions
        }

debugApplyEquationTransformer
    :: Log.DebugApplyEquationOptions
    -> Log.KoreLogOptions
    -> Log.KoreLogOptions
debugApplyEquationTransformer
    debugApplyEquationOptions
    koreLogOptions
  =
    koreLogOptions
        { Log.debugApplyEquationOptions = debugApplyEquationOptions
        }

debugEquationTransformer
    :: Log.DebugEquationOptions
    -> Log.KoreLogOptions
    -> Log.KoreLogOptions
debugEquationTransformer
    debugEquationOptions
    koreLogOptions
  =
    koreLogOptions
        { Log.debugEquationOptions = debugEquationOptions
        }

-- | List of available commands for the Repl. Note that we are always in a proof
-- state. We pick the first available Claim when we initialize the state.
data ReplCommand
    = ShowUsage
    -- ^ This is the default action in case parsing all others fail.
    | Help
    -- ^ Shows the help message.
    | ShowClaim !(Maybe (Either ClaimIndex RuleName))
    -- ^ Show the nth claim or the current claim.
    | ShowAxiom !(Either AxiomIndex RuleName)
    -- ^ Show the nth axiom.
    | Prove !(Either ClaimIndex RuleName)
    -- ^ Drop the current proof state and re-initialize for the nth claim.
    | ShowGraph
        !(Maybe GraphView)
        !(Maybe FilePath)
        !(Maybe Graph.GraphvizOutput)
    -- ^ Show the current execution graph.
    | ProveSteps !Natural
    -- ^ Do n proof steps from current node.
    | ProveStepsF !Natural
    -- ^ Do n proof steps (through branchings) from the current node.
    | SelectNode !ReplNode
    -- ^ Select a different node in the graph.
    | ShowConfig !(Maybe ReplNode)
    -- ^ Show the configuration from the current node.
    | ShowDest !(Maybe ReplNode)
    -- ^ Show the destination from the current node.
    | OmitCell !(Maybe String)
    -- ^ Adds or removes cell to omit list, or shows current omit list.
    | ShowLeafs
    -- ^ Show leafs which can continue evaluation and leafs which are stuck
    | ShowRule !(Maybe ReplNode)
    -- ^ Show the rule(s) that got us to this configuration.
    | ShowRules !(ReplNode, ReplNode)
    -- ^ Show the rules which were applied from the first node
    -- to reach the second.
    | ShowPrecBranch !(Maybe ReplNode)
    -- ^ Show the first preceding branch.
    | ShowChildren !(Maybe ReplNode)
    -- ^ Show direct children of node.
    | Label !(Maybe String)
    -- ^ Show all node labels or jump to a label.
    | LabelAdd !String !(Maybe ReplNode)
    -- ^ Add a label to a node.
    | LabelDel !String
    -- ^ Remove a label.
    | Redirect ReplCommand FilePath
    -- ^ Prints the output of the inner command to the file.
    | Try !RuleReference
    -- ^ Attempt to apply axiom or claim to current node.
    | TryF !RuleReference
    -- ^ Force application of an axiom or claim to current node.
    | Clear !(Maybe ReplNode)
    -- ^ Remove child nodes from graph.
    | Pipe ReplCommand !String ![String]
    -- ^ Pipes a repl command into an external script.
    | SaveSession FilePath
    -- ^ Writes all commands executed in this session to a file on disk.
    | SavePartialProof (Maybe Natural) FilePath
    -- ^ Saves a partial proof to a file on disk.
    | AppendTo ReplCommand FilePath
    -- ^ Appends the output of a command to a file.
    | Alias AliasDefinition
    -- ^ Alias a command.
    | TryAlias ReplAlias
    -- ^ Try running an alias.
    | LoadScript FilePath
    -- ^ Load script from file
    | ProofStatus
    -- ^ Show proof status of each claim
    -- TODO(Ana): 'Log (KoreLogOptions -> KoreLogOptions)', this would need
    -- the parts of the code which depend on the 'Show' instance of 'ReplCommand'
    -- to change. Do the same for Debug..Equation.
    | Log GeneralLogOptions
    -- ^ Setup the Kore logger.
    | DebugAttemptEquation Log.DebugAttemptEquationOptions
    -- ^ Log debugging information about attempting to
    -- apply specific equations.
    | DebugApplyEquation Log.DebugApplyEquationOptions
    -- ^ Log when specific equations apply.
    | DebugEquation Log.DebugEquationOptions
    -- ^ Log the attempts and the applications of specific
    -- equations.
    | Exit
    -- ^ Exit the repl.
    deriving (Eq, Show)

commandSet :: Set String
commandSet = Set.fromList
    [ "help"
    , "claim"
    , "axiom"
    , "prove"
    , "graph"
    , "step"
    , "stepf"
    , "select"
    , "config"
    , "omit"
    , "leafs"
    , "rule"
    , "prec-branch"
    , "proof-status"
    , "children"
    , "label"
    , "try"
    , "tryf"
    , "clear"
    , "save-session"
    , "alias"
    , "load"
    , "log"
    , "exit"
    ]

-- | Please remember to update this text whenever you update the ADT above.
helpText :: String
helpText =
    "Available commands in the Kore REPL: \n\
    \help                                     shows this help message\n\
    \claim [n|<name>]                         shows the nth claim, the claim with\
                                              \ <name> or (default) the currently\
                                              \ focused claim\n\
    \axiom <n|name>                           shows the nth axiom or the axiom\
                                              \ with <name>\n\
    \prove <n|name>                           initializes proof mode for the nth\
                                              \ claim or for the claim with <name>\n\
    \graph [view] [file] [format]             shows the current proof graph (*),\
                                              \ 'expanded' or 'collapsed';\
                                              \ or saves it as jpeg, png, pdf or svg\n\
    \step [n]                                 attempts to run 'n' proof steps at\
                                              \ the current node (n=1 by default)\n\
    \stepf [n]                                like step, but goes through\
                                              \ branchings to the first\
                                              \ interesting branching node (**)\n\
    \select <n>                               select node id 'n' from the graph\n\
    \config [n]                               shows the config for node 'n'\
                                              \ (defaults to current node)\n\
    \dest [n]                                 shows the destination for node 'n'\
                                              \ (defaults to current node)\n\
    \omit [cell]                              adds or removes cell to omit list\
                                              \ (defaults to showing the omit\
                                              \ list)\n\
    \leafs                                    shows unevaluated or stuck leafs\n\
    \rule [n]                                 shows the rule for node 'n'\
                                              \ (defaults to current node)\n\
    \rules <n1> <n2>                          shows the rules applied on the path\
                                              \ between nodes n1 and n2\n\
    \prec-branch [n]                          shows first preceding branch\
                                              \ (defaults to current node)\n\
    \children [n]                             shows direct children of node\
                                              \ (defaults to current node)\n\
    \label                                    shows all node labels\n\
    \label <l>                                jump to a label\n\
    \label <+l> [n]                           add a new label for a node\
                                              \ (defaults to current node)\n\
    \label <-l>                               remove a label\n\
    \try (<a|c><num>)|<name>                  attempts <a>xiom or <c>laim at\
                                              \ index <num> or rule with <name>\n\
    \tryf (<a|c><num>)|<name>                 like try, but if successful, it will apply the axiom or claim.\n\
    \clear [n]                                removes all the node's children from the\
                                              \ proof graph (***)\
                                              \ (defaults to current node)\n\
    \save-session file                        saves the current session to file\n\
    \save-partial-proof [n] file              writes a new claim with the\
                                              \ config 'n' as its LHS and all\
                                              \ other claims marked as trusted\n\
    \alias <name> = <command>                 adds as an alias for <command>\n\
    \<alias>                                  runs an existing alias\n\
    \load file                                loads the file as a repl script\n\
    \proof-status                             shows status for each claim\n\
    \log [<severity>] \"[\"<entry>\"]\"           configures logging; <severity> can be debug ... error; [<entry>] is a list formed by types below;\n\
    \    <type> <switch-timestamp>            <type> can be stderr or 'file filename'; <switch-timestamp> can be (enable|disable)-log-timestamps;\n\
    \debug[-type-]equation [eqId1] [eqId2] .. show debugging information for specific equations;\
                                              \ [-type-] can be '-attempt-', '-apply-' or '-',\n\
    \exit                                     exits the repl\
    \\n\n\
    \Available modifiers:\n\
    \<command> > file                         prints the output of 'command'\
                                              \ to file\n\
    \<command> >> file                        appends the output of 'command'\
                                              \ to file\n\
    \<command> | external_script              pipes command to external script\
                                              \ and prints the result in the\
                                              \ repl; can be redirected using > or >>\n\
    \\n\
    \Rule names can be added in two ways:\n\
    \    a) rule <k> ... </k> [label(myName)]\n\
    \       - can be used as-is\n\
    \       - ! do not add names which match the indexing syntax for the try command\n\
    \    b) rule [myName] : <k> ... </k>\n\
    \       - need to be prefixed with the module name, e.g. IMP.myName\n\
    \\nAvailable entry types:\n"
    <> entriesForHelp
    <>
    "\n\
    \(*) If an edge is labeled as Simpl/RD it means that the target node\n\
    \ was reached using either the SMT solver or the Remove Destination step.\n\
    \    A green node represents the proof has completed on\
    \ that respective branch. \n\
    \    A red node represents a stuck configuration.\n\
    \(**) An interesting branching node has at least two children which\n\
    \ contain non-bottom leaves in their subtrees. If no such node exists,\n\
    \ the current node is advanced to the (only) non-bottom leaf. If no such\n\
    \ leaf exists (i.e the proof is complete), the current node remains the same\n\
    \ and a message is emitted.\n\
    \(***) The clear command doesn't allow the removal of nodes which are direct\n\
    \ descendants of branchings. The steps which create branchings cannot be\n\
    \ partially redone. Therefore, if this were allowed it would result in invalid proofs.\n"
    <> "\nFor more details see https://github.com/kframework/kore/wiki/Kore-REPL#available-commands-in-the-kore-repl\n"


entriesForHelp :: String
entriesForHelp =
    zipWith3
        (\e1 e2 e3 -> align e1 <> align e2 <> align e3)
        column1
        column2
        column3
    & unlines
  where
    entries :: [String]
    entries =
        Log.entryTypeReps
        & fmap show
        & sort
        & (<> ["", ""])
    align entry = entry <> replicate (40 - length entry) ' '
    columnLength = length entries `div` 3
    (column1And2, column3) = splitAt (2 * columnLength) entries
    (column1, column2) = splitAt columnLength column1And2

-- | Determines whether the command needs to be stored or not. Commands that
-- affect the outcome of the proof are stored.
shouldStore :: ReplCommand -> Bool
shouldStore =
    \case
        ShowUsage        -> False
        Help             -> False
        ShowClaim _      -> False
        ShowAxiom _      -> False
        ShowGraph _ _ _  -> False
        ShowConfig _     -> False
        ShowLeafs        -> False
        ShowRule _       -> False
        ShowPrecBranch _ -> False
        ShowChildren _   -> False
        SaveSession _    -> False
        ProofStatus      -> False
        Try _            -> False
        Exit             -> False
        _                -> True

-- Type synonym for the actual type of the execution graph.
type ExecutionGraph rule =
    Strategy.ExecutionGraph
        CommonProofState
        rule

type InnerGraph rule =
    Gr CommonProofState (Seq rule)

type Claim = ReachabilityRule
type Axiom = Rule Claim

-- | State for the repl.
data ReplState = ReplState
    { axioms     :: [Axiom]
    -- ^ List of available axioms
    , claims     :: [Claim]
    -- ^ List of claims to be proven
    , claim      :: Claim
    -- ^ Currently focused claim in the repl
    , claimIndex :: ClaimIndex
    -- ^ Index of the currently focused claim in the repl
    , graphs     :: Map ClaimIndex (ExecutionGraph Axiom)
    -- ^ Execution graph for the current proof; initialized with root = claim
    , node       :: ReplNode
    -- ^ Currently selected node in the graph; initialized with node = root
    , commands   :: Seq String
    -- ^ All commands evaluated by the current repl session
    , omit       :: Set String
    -- ^ The omit list, initially empty
    , labels  :: Map ClaimIndex (Map String ReplNode)
    -- ^ Map from labels to nodes
    , aliases :: Map String AliasDefinition
    -- ^ Map of command aliases
    , koreLogOptions :: !Log.KoreLogOptions
    -- ^ The log level, log scopes and log type decide what gets logged and
    -- where.
    }
    deriving (GHC.Generic)

-- | Configuration environment for the repl.
data Config m = Config
    { stepper
        :: [Claim]
        -> [Axiom]
        -> ExecutionGraph Axiom
        -> ReplNode
        -> m (ExecutionGraph Axiom)
    -- ^ Stepper function
    , unifier
        :: SideCondition VariableName
        -> TermLike VariableName
        -> TermLike VariableName
        -> UnifierWithExplanation m (Condition VariableName)
    -- ^ Unifier function, it is a partially applied 'unificationProcedure'
    --   where we discard the result since we are looking for unification
    --   failures
    , logger  :: MVar (LogAction IO ActualEntry)
    -- ^ Logger function, see 'logging'.
    , outputFile :: OutputFile
    -- ^ Output resulting pattern to this file.
    , mainModuleName :: ModuleName
    }
    deriving (GHC.Generic)

-- | Unifier that stores the first 'explainBottom'.
-- See 'runUnifierWithExplanation'.
newtype UnifierWithExplanation m a =
    UnifierWithExplanation
        { getUnifierWithExplanation
            :: UnifierT (AccumT (First ReplOutput) m) a
        }
  deriving (Alternative, Applicative, Functor, Monad, MonadPlus)

instance Monad m => MonadLogic (UnifierWithExplanation m) where
    msplit act =
        UnifierWithExplanation
        $ msplit (getUnifierWithExplanation act) >>= return . wrapNext
      where
        wrapNext = (fmap . fmap) UnifierWithExplanation

deriving instance MonadSMT m => MonadSMT (UnifierWithExplanation m)

instance MonadTrans UnifierWithExplanation where
    lift = UnifierWithExplanation . lift . lift
    {-# INLINE lift #-}

instance MonadLog m => MonadLog (UnifierWithExplanation m) where
    logEntry entry = UnifierWithExplanation $ logEntry entry
    {-# INLINE logEntry #-}
    logWhile entry ma =
        UnifierWithExplanation $ logWhile entry (getUnifierWithExplanation ma)
    {-# INLINE logWhile #-}

instance MonadSimplify m => MonadSimplify (UnifierWithExplanation m) where
    localSimplifierAxioms locally (UnifierWithExplanation unifierT) =
        UnifierWithExplanation $ localSimplifierAxioms locally unifierT

instance MonadSimplify m => MonadUnify (UnifierWithExplanation m) where
    explainBottom info first second =
        UnifierWithExplanation
        . Monad.Trans.lift
        . Monad.Accum.add
        . First
        . Just $ ReplOutput
            [ AuxOut . show $ info <> "\n"
            , AuxOut "When unifying:\n"
            , KoreOut $ (show . Pretty.indent 4 . unparse $ first) <> "\n"
            , AuxOut "With:\n"
            , KoreOut $ (show . Pretty.indent 4 . unparse $ second) <> "\n"
            ]

-- | Result after running one or multiple proof steps.
data StepResult
    = NoResult
    -- ^ reached end of proof on current branch
    | SingleResult ReplNode
    -- ^ single follow-up configuration
    | BranchResult [ReplNode]
    -- ^ configuration branched
    deriving (Show)

data NodeState = StuckNode | UnevaluatedNode
    deriving (Eq, Ord, Show)

data AliasError
    = NameAlreadyDefined
    | UnknownCommand

data GraphProofStatus
    = NotStarted
    | Completed
    | InProgress [Graph.Node]
    | StuckProof [Graph.Node]
    | TrustedClaim
    deriving (Eq, Show)

makeAuxReplOutput :: String -> ReplOutput
makeAuxReplOutput str =
    ReplOutput . return . AuxOut $ str <> "\n"

makeKoreReplOutput :: String -> ReplOutput
makeKoreReplOutput str =
    ReplOutput . return . KoreOut $ str <> "\n"

runUnifierWithExplanation
    :: forall m a
    .  MonadSimplify m
    => UnifierWithExplanation m a
    -> m (Either ReplOutput (NonEmpty a))
runUnifierWithExplanation (UnifierWithExplanation unifier) =
    failWithExplanation <$> unificationResults
  where
    unificationResults
        ::  m ([a], First ReplOutput)
    unificationResults =
        flip runAccumT mempty
        . Monad.Unify.runUnifierT Not.notSimplifier
        $ unifier
    failWithExplanation
        :: ([a], First ReplOutput)
        -> Either ReplOutput (NonEmpty a)
    failWithExplanation (results, explanation) =
        case results of
            [] ->
                Left $ fromMaybe
                    (makeAuxReplOutput "No explanation given")
                    (getFirst explanation)
            r : rs -> Right (r :| rs)
