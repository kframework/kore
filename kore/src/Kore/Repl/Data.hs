{-|
Module      : Kore.Repl.Data
Description : REPL data structures.
Copyright   : (c) Runtime Verification, 2019
License     : NCSA
Maintainer  : vladimir.ciobanu@runtimeverification.com
-}

{-# LANGUAGE TemplateHaskell #-}

module Kore.Repl.Data
    ( ReplCommand (..)
    , helpText
    , ExecutionGraph
    , AxiomIndex (..), ClaimIndex (..)
    , ReplNode (..)
    , ReplState (..)
    , NodeState (..)
    , GraphProofStatus (..)
    , AliasDefinition (..), ReplAlias (..), AliasArgument(..), AliasError (..)
    , InnerGraph
    , lensAxioms, lensClaims, lensClaim
    , lensGraphs, lensNode, lensStepper
    , lensLabels, lensOmit, lensUnifier
    , lensCommands, lensAliases, lensClaimIndex
    , lensLogging, lensLogger
    , lensOutputFile
    , shouldStore
    , commandSet
    , UnifierWithExplanation (..)
    , runUnifierWithExplanation
    , StepResult(..)
    , LogType (..)
    , ReplScript (..)
    , ReplMode (..)
    , OutputFile (..)
    ) where

import           Control.Applicative
                 ( Alternative )
import           Control.Concurrent.MVar
import qualified Control.Lens.TH.Rules as Lens
import           Control.Monad.Trans.Accum
                 ( AccumT, runAccumT )
import qualified Control.Monad.Trans.Accum as Monad.Accum
import qualified Control.Monad.Trans.Class as Monad.Trans
import qualified Data.Graph.Inductive.Graph as Graph
import           Data.Graph.Inductive.PatriciaTree
                 ( Gr )
import           Data.List.NonEmpty
                 ( NonEmpty (..) )
import           Data.Map.Strict
                 ( Map )
import           Data.Maybe
                 ( fromMaybe )
import           Data.Monoid
                 ( First (..) )
import           Data.Sequence
                 ( Seq )
import           Data.Set
                 ( Set )
import qualified Data.Set as Set
import           Data.Text.Prettyprint.Doc
                 ( Doc )
import qualified Data.Text.Prettyprint.Doc as Pretty
import           Numeric.Natural

import qualified Kore.Internal.Predicate as IPredicate
import           Kore.Internal.TermLike
                 ( TermLike )
import qualified Kore.Logger.Output as Logger
import           Kore.OnePath.StrategyPattern
import           Kore.OnePath.Verification
                 ( Axiom (..), Claim )
import           Kore.Step.Rule
                 ( RewriteRule (..) )
import           Kore.Step.Simplification.Data
                 ( MonadSimplify, Simplifier )
import qualified Kore.Step.Strategy as Strategy
import           Kore.Syntax.Variable
                 ( Variable )
import           Kore.Unification.Error
import           Kore.Unification.Unify
                 ( MonadUnify, UnifierT (..) )
import qualified Kore.Unification.Unify as Monad.Unify
import           Kore.Unparser
                 ( unparse )
import           SMT
                 ( MonadSMT )

-- | Represents an optional file name which contains a sequence of
-- repl commands.
newtype ReplScript = ReplScript
    { unReplScript :: Maybe FilePath
    } deriving (Eq, Show)

data ReplMode = Interactive | RunScript
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
    | LogToStdOut
    | LogToFile !FilePath
    deriving (Eq, Show)

-- | List of available commands for the Repl. Note that we are always in a proof
-- state. We pick the first available Claim when we initialize the state.
data ReplCommand
    = ShowUsage
    -- ^ This is the default action in case parsing all others fail.
    | Help
    -- ^ Shows the help message.
    | ShowClaim !(Maybe ClaimIndex)
    -- ^ Show the nth claim or the current claim.
    | ShowAxiom !AxiomIndex
    -- ^ Show the nth axiom.
    | Prove !ClaimIndex
    -- ^ Drop the current proof state and re-initialize for the nth claim.
    | ShowGraph !(Maybe FilePath)
    -- ^ Show the current execution graph.
    | ProveSteps !Natural
    -- ^ Do n proof steps from current node.
    | ProveStepsF !Natural
    -- ^ Do n proof steps (through branchings) from the current node.
    | SelectNode !ReplNode
    -- ^ Select a different node in the graph.
    | ShowConfig !(Maybe ReplNode)
    -- ^ Show the configuration from the current node.
    | OmitCell !(Maybe String)
    -- ^ Adds or removes cell to omit list, or shows current omit list.
    | ShowLeafs
    -- ^ Show leafs which can continue evaluation and leafs which are stuck
    | ShowRule !(Maybe ReplNode)
    -- ^ Show the rule(s) that got us to this configuration.
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
    | Try !(Either AxiomIndex ClaimIndex)
    -- ^ Attempt to apply axiom or claim to current node.
    | TryF !(Either AxiomIndex ClaimIndex)
    -- ^ Force application of an axiom or claim to current node.
    | Clear !(Maybe ReplNode)
    -- ^ Remove child nodes from graph.
    | Pipe ReplCommand !String ![String]
    -- ^ Pipes a repl command into an external script.
    | SaveSession FilePath
    -- ^ Writes all commands executed in this session to a file on disk.
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
    | Log Logger.Severity LogType
    -- ^ Setup the Kore logger.
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
    , "omit"
    , "leafs"
    , "rule"
    , "prec-branch"
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
    \help                                  shows this help message\n\
    \claim [n]                             shows the nth claim or if\
                                           \ used without args shows the\
                                           \ currently focused claim\n\
    \axiom <n>                             shows the nth axiom\n\
    \prove <n>                             initializes proof mode for the nth\
                                           \ claim\n\
    \graph [file]                          shows the current proof graph (*)\n\
    \                                      (saves image in .jpeg format if file\
                                           \ argument is given; file extension is\
                                           \ added automatically)\n\
    \step [n]                              attempts to run 'n' proof steps at\
                                           \the current node (n=1 by default)\n\
    \stepf [n]                             attempts to run 'n' proof steps at\
                                           \ the current node, stepping through\
                                           \ branchings (n=1 by default)\n\
    \select <n>                            select node id 'n' from the graph\n\
    \config [n]                            shows the config for node 'n'\
                                           \ (defaults to current node)\n\
    \omit [cell]                           adds or removes cell to omit list\
                                           \ (defaults to showing the omit\
                                           \ list)\n\
    \leafs                                 shows unevaluated or stuck leafs\n\
    \rule [n]                              shows the rule for node 'n'\
                                           \ (defaults to current node)\n\
    \prec-branch [n]                       shows first preceding branch\
                                           \ (defaults to current node)\n\
    \children [n]                          shows direct children of node\
                                           \ (defaults to current node)\n\
    \label                                 shows all node labels\n\
    \label <l>                             jump to a label\n\
    \label <+l> [n]                        add a new label for a node\
                                           \ (defaults to current node)\n\
    \label <-l>                            remove a label\n\
    \try <a|c><num>                        attempts <a>xiom or <c>laim at\
                                           \ index <num>\n\
    \tryf <a|c><num>                       attempts <a>xiom or <c>laim at\
                                           \ index <num> and if successful, it\
                                           \ will apply it.\n\
    \clear [n]                             removes all node children from the\
                                           \ proof graph\n\
    \                                      (defaults to current node)\n\
    \save-session file                     saves the current session to file\n\
    \alias <name> = <command>              adds as an alias for <command>\n\
    \<alias>                               runs an existing alias\n\
    \load file                             loads the file as a repl script\n\
    \proof-status                          shows status for each claim\n\
    \log <severity> <type>                 configures the logging outout\n\
                                           \<severity> can be debug, info, warning,\
                                           \error, or critical\n\
    \                                      <type> can be NoLogging, LogToStdOut,\
                                           \or LogToFile filename\n\
    \exit                                  exits the repl\
    \\n\
    \Available modifiers:\n\
    \<command> > file                      prints the output of 'command'\
                                           \ to file\n\
    \<command> >> file                     appends the output of 'command'\
                                           \ to file\n\
    \<command> | external script           pipes command to external script\
                                           \ and prints the result in the\
                                           \ repl\n\
    \<command> | external script > file    pipes and then redirects the output\
                                           \ of the piped command to a file\n\
    \<command> | external script >> file   pipes and then appends the output\
                                           \ of the piped command to a file\n\
    \\n\
    \(*) If an edge is labeled as Simpl/RD it means that\
    \ either the target node was reached using the SMT solver\
    \ or it was reached through the Remove Destination step."

-- | Determines whether the command needs to be stored or not. Commands that
-- affect the outcome of the proof are stored.
shouldStore :: ReplCommand -> Bool
shouldStore =
    \case
        ShowUsage        -> False
        Help             -> False
        ShowClaim _      -> False
        ShowAxiom _      -> False
        ShowGraph _      -> False
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
type ExecutionGraph =
    Strategy.ExecutionGraph
        CommonStrategyPattern
        (RewriteRule Variable)

type InnerGraph =
    Gr CommonStrategyPattern (Seq (RewriteRule Variable))

-- | State for the rep.
data ReplState claim = ReplState
    { axioms     :: [Axiom]
    -- ^ List of available axioms
    , claims     :: [claim]
    -- ^ List of claims to be proven
    , claim      :: claim
    -- ^ Currently focused claim in the repl
    , claimIndex :: ClaimIndex
    -- ^ Index of the currently focused claim in the repl
    , graphs     :: Map ClaimIndex ExecutionGraph
    -- ^ Execution graph for the current proof; initialized with root = claim
    , node       :: ReplNode
    -- ^ Currently selected node in the graph; initialized with node = root
    , commands   :: Seq String
    -- ^ All commands evaluated by the current repl session
    -- TODO(Vladimir): This should be a Set String instead.
    , omit       :: [String]
    -- ^ The omit list, initially empty
    , stepper
        :: Claim claim
        => claim
        -> [claim]
        -> [Axiom]
        -> ExecutionGraph
        -> ReplNode
        -> Simplifier ExecutionGraph
    -- ^ Stepper function, it is a partially applied 'verifyClaimStep'
    , unifier
        :: TermLike Variable
        -> TermLike Variable
        -> UnifierWithExplanation (IPredicate.Predicate Variable)
    -- ^ Unifier function, it is a partially applied 'unificationProcedure'
    --   where we discard the result since we are looking for unification
    --   failures
    , labels  :: Map ClaimIndex (Map String ReplNode)
    -- ^ Map from labels to nodes
    , aliases :: Map String AliasDefinition
    -- ^ Map of command aliases
    , logging :: (Logger.Severity, LogType)
    , logger  :: MVar (Logger.LogAction IO Logger.LogMessage)
    , outputFile :: OutputFile
    }

type Explanation = Doc ()

-- | Unifier that stores the first 'explainBottom'.
-- See 'runUnifierWithExplanation'.
newtype UnifierWithExplanation a =
    UnifierWithExplanation
        { getUnifierWithExplanation
            :: UnifierT (AccumT (First Explanation) Simplifier) a
        }
  deriving (Alternative, Applicative, Functor, Monad)

deriving instance MonadSMT UnifierWithExplanation

instance Logger.WithLog Logger.LogMessage UnifierWithExplanation where
    askLogAction =
        Logger.hoistLogAction UnifierWithExplanation
        <$> UnifierWithExplanation Logger.askLogAction
    {-# INLINE askLogAction #-}

    localLogAction locally =
        UnifierWithExplanation
        . Logger.localLogAction locally
        . getUnifierWithExplanation
    {-# INLINE localLogAction #-}

deriving instance MonadSimplify UnifierWithExplanation

instance MonadUnify UnifierWithExplanation where
    throwSubstitutionError =
        UnifierWithExplanation . Monad.Unify.throwSubstitutionError
    throwUnificationError =
        UnifierWithExplanation . Monad.Unify.throwUnificationError

    gather =
        UnifierWithExplanation . Monad.Unify.gather . getUnifierWithExplanation
    scatter = UnifierWithExplanation . Monad.Unify.scatter

    explainBottom info first second =
        UnifierWithExplanation
        . Monad.Trans.lift
        . Monad.Accum.add
        . First
        . Just $ Pretty.vsep
            [ info
            , "When unifying:"
            , Pretty.indent 4 $ unparse first
            , "With:"
            , Pretty.indent 4 $ unparse second
            ]

runUnifierWithExplanation
    :: forall a
    .  UnifierWithExplanation a
    -> Simplifier (Either Explanation (NonEmpty a))
runUnifierWithExplanation (UnifierWithExplanation unifier) =
    either explainError failWithExplanation <$> unificationResults
  where
    unificationResults
        ::  Simplifier
                (Either UnificationOrSubstitutionError ([a], First Explanation))
    unificationResults =
        fmap (\(r, ex) -> flip (,) ex <$> r)
        . flip runAccumT mempty
        . Monad.Unify.runUnifierT
        $ unifier
    explainError = Left . Pretty.pretty
    failWithExplanation (results, explanation) =
        case results of
            [] -> Left $ fromMaybe "No explanation given" (getFirst explanation)
            r : rs -> Right (r :| rs)

Lens.makeLenses ''ReplState

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

