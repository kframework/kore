{-|
Module      : Kore.Repl
Description : Logging functions.
Copyright   : (c) Runtime Verification, 2019
License     : NCSA
Maintainer  : vladimir.ciobanu@runtimeverification.com
-}

{-# LANGUAGE TemplateHaskell #-}

module Kore.Repl
    ( runRepl
    , ReplState (..)
    ) where

import           Control.Exception
                 ( AsyncException (UserInterrupt) )
import           Control.Lens
                 ( (.=) )
import qualified Control.Lens as Lens hiding
                 ( makeLenses )
import qualified Control.Lens.TH.Rules as Lens
import           Control.Monad.Catch
                 ( catch )
import           Control.Monad.Extra
                 ( whileM )
import           Control.Monad.IO.Class
                 ( MonadIO, liftIO )
import           Control.Monad.State.Strict
                 ( StateT )
import           Control.Monad.State.Strict
                 ( evalStateT, get )
import           Control.Monad.State.Strict
                 ( lift )
import           Data.Functor
                 ( ($>) )
import           Data.Graph.Inductive.Graph
                 ( Graph )
import qualified Data.Graph.Inductive.Graph as Graph
import qualified Data.GraphViz as Graph
import           Data.Maybe
                 ( listToMaybe )
import           System.IO
                 ( hFlush, stdout )
import           Text.Megaparsec
                 ( Parsec, option, parseMaybe, (<|>) )
import           Text.Megaparsec.Char
import           Text.Megaparsec.Char.Lexer
                 ( decimal, signed )

import           Control.Monad.Extra
                 ( loopM )
import qualified Kore.AST.Common as Kore
                 ( Variable )
import           Kore.AST.MetaOrObject
                 ( MetaOrObject )
import           Kore.IndexedModule.MetadataTools
                 ( MetadataTools )
import           Kore.OnePath.Step
                 ( CommonStrategyPattern, StrategyPattern (..) )
import           Kore.OnePath.Verification
                 ( verifyClaimStep )
import           Kore.OnePath.Verification
                 ( Axiom (..) )
import           Kore.OnePath.Verification
                 ( Claim (..) )
import           Kore.Step.Axiom.Data
                 ( BuiltinAndAxiomSimplifierMap )
import           Kore.Step.AxiomPatterns
                 ( RewriteRule (..) )
import           Kore.Step.AxiomPatterns
                 ( RulePattern (..) )
import           Kore.Step.Representation.ExpandedPattern
                 ( Predicated (..) )
import           Kore.Step.Simplification.Data
                 ( Simplifier )
import           Kore.Step.Simplification.Data
                 ( StepPatternSimplifier )
import           Kore.Step.Simplification.Data
                 ( PredicateSubstitutionSimplifier )
import           Kore.Step.StepperAttributes
                 ( StepperAttributes )
import qualified Kore.Step.Strategy as Strategy
import           Kore.Unparser
                 ( unparseToString )

-- Type synonym for the actual type of the execution graph.
type ExecutionGraph level = Strategy.ExecutionGraph (CommonStrategyPattern level)

-- | State for the rep.
data ReplState level = ReplState
    { axioms  :: [Axiom level]
    -- ^ List of available axioms
    , claims  :: [Claim level]
    -- ^ List of claims to be proven
    , claim   :: Claim level
    -- ^ Currently focused claim in the repl
    , graph   :: ExecutionGraph level
    -- ^ Execution graph for the current proof; initialized with root = claim
    , node    :: Graph.Node
    -- ^ Currently selected node in the graph; initialized with node = root
    , stepper :: StateT (ReplState level) Simplifier Bool
    -- ^ Stepper function, it is a partially applied 'verifyClaimStep'
    }

Lens.makeLenses ''ReplState

-- | Runs the repl for proof mode. It requires all the tooling and simplifiers
-- that would otherwise be required in the proof and allows for step-by-step
-- execution of proofs. Currently works via stdin/stdout interaction.
runRepl
    :: forall level
    .  MetaOrObject level
    => MetadataTools level StepperAttributes
    -- ^ tools required for the proof
    -> StepPatternSimplifier level
    -- ^ pattern simplifier
    -> PredicateSubstitutionSimplifier level
    -- ^ predicate simplifier
    -> BuiltinAndAxiomSimplifierMap level
    -- ^ builtin simplifier
    -> [Axiom level]
    -- ^ list of axioms to used in the proof
    -> [Claim level]
    -- ^ list of claims to be proven
    -> Simplifier ()
runRepl tools simplifier predicateSimplifier axiomToIdSimplifier axioms' claims'
  = do
    replGreeting
    evalStateT (whileM repl0) state

  where
    repl0 :: StateT (ReplState level) Simplifier Bool
    repl0 = do
        command <- maybe ShowUsage id . parseMaybe commandParser <$> prompt
        replInterpreter command

    state :: ReplState level
    state =
        ReplState
            { axioms  = axioms'
            , claims  = claims'
            , claim   = firstClaim
            , graph   = firstClaimExecutionGraph
            , node    = (Strategy.root firstClaimExecutionGraph)
            , stepper = stepper0
            }

    firstClaim :: Claim level
    firstClaim = maybe (error "No claims found") id . listToMaybe $ claims'

    firstClaimExecutionGraph :: ExecutionGraph level
    firstClaimExecutionGraph = emptyExecutionGraph firstClaim

    stepper0 :: StateT (ReplState level) Simplifier Bool
    stepper0 = do
        ReplState
            { claims
            , axioms
            , graph
            , claim
            , node
            } <- get
        if Graph.outdeg (Strategy.graph graph) node == 0
            then do
                graph' <- lift . catchInterruptWithDefault graph
                    $ verifyClaimStep
                        tools
                        simplifier
                        predicateSimplifier
                        axiomToIdSimplifier
                        claim
                        claims
                        axioms
                        graph
                        node
                lensGraph .= graph'
                pure True
            else pure False

    catchInterruptWithDefault :: a -> Simplifier a -> Simplifier a
    catchInterruptWithDefault def sa =
        catch sa $ \UserInterrupt -> do
            liftIO $ putStrLn "Step evaluation interrupted."
            pure def

    replGreeting :: MonadIO m => m ()
    replGreeting =
        liftIO $
            putStrLn "Welcome to the Kore Repl! Use 'help' to get started.\n"

    prompt :: StateT (ReplState level) Simplifier String
    prompt = do
        node <- Lens.use lensNode
        liftIO $ do
            putStr $ "Kore (" <> show node <> ")> "
            hFlush stdout
            getLine

-- | List of available commands for the Repl. Note that we are always in a proof
-- state. We pick the first available Claim when we initialize the state.
data ReplCommand
    = ShowUsage
    -- ^ This is the default action in case parsing all others fail.
    | Help
    -- ^ Shows the help message.
    | ShowClaim !Int
    -- ^ Show the nth claim.
    | ShowAxiom !Int
    -- ^ Show the nth axiom.
    | Prove !Int
    -- ^ Drop the current proof state and re-initialize for the nth claim.
    | ShowGraph
    -- ^ Show the current execution graph.
    | ProveSteps !Int
    -- ^ Do n proof steps from curent node.
    | SelectNode !Int
    -- ^ Select a different node in the graph.
    | ShowConfig (Maybe Int)
    -- ^ Show the configuration from the current node.
    | Exit
    -- ^ Exit the repl.

-- | Please remember to update this text whenever you update the ADT above.
helpText :: String
helpText =
    "Available commands in the Kore REPL: \n\
    \help                    shows this help message\n\
    \claim <n>               shows the nth claim\n\
    \axiom <n>               shows the nth axiom\n\
    \prove <n>               initializez proof mode for the nth \
                             \claim\n\
    \graph                   shows the current proof graph\n\
    \step [n]                attempts to run 'n' proof steps at\
                             \the current node (n=1 by default)\n\
    \select <n>              select node id 'n' from the graph\n\
    \config                  shows the config for the selected \
                             \node\n\
    \exit                    exits the repl"

type Parser = Parsec String String

commandParser :: Parser ReplCommand
commandParser =
    help0
    <|> showClaim0
    <|> showAxiom0
    <|> prove0
    <|> showGraph0
    <|> proveSteps0
    <|> selectNode0
    <|> showConfig0
    <|> exit0
    <|> pure ShowUsage
  where
    help0 :: Parser ReplCommand
    help0 = string "help" $> Help

    showClaim0 :: Parser ReplCommand
    showClaim0 = fmap ShowClaim $ string "claim" *> space *> decimal

    showAxiom0 :: Parser ReplCommand
    showAxiom0 = fmap ShowAxiom $ string "axiom" *> space *> decimal

    prove0 :: Parser ReplCommand
    prove0 = fmap Prove $ string "prove" *> space *> decimal

    showGraph0 :: Parser ReplCommand
    showGraph0 = ShowGraph <$ string "graph"

    proveSteps0 :: Parser ReplCommand
    proveSteps0 = fmap ProveSteps $ string "step" *> space *> option 1 decimal

    selectNode0 :: Parser ReplCommand
    selectNode0 =
        fmap SelectNode $ string "select" *> space *> signed space decimal

    showConfig0 :: Parser ReplCommand
    showConfig0 = fmap ShowConfig $ string "config" *> (fmap Just (space *> decimal) <|> pure Nothing)

    exit0 :: Parser ReplCommand
    exit0 = Exit <$ string "exit"

replInterpreter
    :: forall level
    .  MetaOrObject level
    => ReplCommand
    -> StateT (ReplState level) Simplifier Bool
replInterpreter =
    \case
        ShowUsage -> showUsage0 $> True
        Help -> help0 $> True
        ShowClaim c -> showClaim0 c $> True
        ShowAxiom a -> showAxiom0 a $> True
        Prove i -> prove0 i $> True
        ShowGraph -> showGraph0 $> True
        ProveSteps n -> proveSteps0 n $> True
        SelectNode i -> selectNode0 i $> True
        ShowConfig mc -> showConfig0 mc $> True
        Exit -> pure False
  where
    showUsage0 :: StateT st Simplifier ()
    showUsage0 =
        putStrLn' "Could not parse command, try using 'help'."

    help0 :: StateT st Simplifier ()
    help0 =
        putStrLn' helpText

    showClaim0 :: Int -> StateT (ReplState level) Simplifier ()
    showClaim0 index = do
        claim <- Lens.preuse $ lensClaims . Lens.element index
        putStrLn' $ maybe indexNotFound (unparseToString . unClaim) claim

    showAxiom0 :: Int -> StateT (ReplState level) Simplifier ()
    showAxiom0 index = do
        axiom <- Lens.preuse $ lensAxioms . Lens.element index
        putStrLn' $ maybe indexNotFound (unparseToString . unAxiom) axiom

    prove0 :: Int -> StateT (ReplState level) Simplifier ()
    prove0 index = do
        claim' <- Lens.preuse $ lensClaims . Lens.element index
        case claim' of
            Nothing -> putStrLn' indexNotFound
            Just claim -> do
                let
                    graph@Strategy.ExecutionGraph { root }
                        = emptyExecutionGraph claim
                lensGraph .= graph
                lensClaim .= claim
                lensNode  .= root
                putStrLn' "Execution Graph initiated"

    showGraph0 :: StateT (ReplState level) Simplifier ()
    showGraph0 = do
        Strategy.ExecutionGraph { graph } <- Lens.use lensGraph
        liftIO $ showDotGraph graph


    proveSteps0 :: Int -> StateT (ReplState level) Simplifier ()
    proveSteps0 n = do
        result <- loopM performStepNoBranching (n, Success)
        case result of
            (0, Success) -> pure ()
            (done, res) ->
                putStrLn'
                    $ "Stopped after "
                    <> show (n - done - 1)
                    <> " step(s) due to "
                    <> show res

    selectNode0 :: Int -> StateT (ReplState level) Simplifier ()
    selectNode0 i = do
        Strategy.ExecutionGraph { graph } <- Lens.use lensGraph
        if i `elem` Graph.nodes graph
            then lensNode .= i
            else putStrLn' "Invalid node!"

    showConfig0 :: Maybe Int -> StateT (ReplState level) Simplifier ()
    showConfig0 configNode = do
        Strategy.ExecutionGraph { graph } <- Lens.use lensGraph
        node <- Lens.use lensNode
        let node' = maybe node id configNode
        if node' `elem` Graph.nodes graph
           then do
               putStrLn' $ "Config at node " <> show node' <> " is:"
               putStrLn'
                   . unparseStrategy
                   . Graph.lab'
                   . Graph.context graph
                   $ node'
           else putStrLn' "Invalid node!"


    performSingleStep
        :: StateT (ReplState level) Simplifier StepResult
    performSingleStep = do
        f <- Lens.use lensStepper
        node <- Lens.use lensNode
        res <- f
        if res
            then do
                Strategy.ExecutionGraph { graph } <- Lens.use lensGraph
                let
                    context = Graph.context graph node
                case Graph.suc' context of
                    [] -> pure NoChildNodes
                    [configNo] -> do
                        lensNode .= configNo
                        pure Success
                    neighbors -> pure (Branch neighbors)
            else pure NodeAlreadyEvaluated

    -- | Performs n proof steps, picking the next node unless branching occurs.
    -- Returns 'Left' while it has to continue looping, and 'Right' when done
    -- or when execution branches or proof finishes earlier than the counter.
    --
    -- See 'loopM' for details.
    performStepNoBranching
        :: (Int, StepResult)
        -- ^ (current step, last result)
        -> StateT
            (ReplState level)
            Simplifier
                (Either
                     (Int, StepResult)
                     (Int, StepResult)
                )
    performStepNoBranching (0, res) =
        pure $ Right (0, res)
    performStepNoBranching (n, Success) = do
        res <- performSingleStep
        pure $ Left (n-1, res)
    performStepNoBranching (n, res) =
        pure $ Right (n, res)

    unparseStrategy :: CommonStrategyPattern level -> String
    unparseStrategy =
        \case
            Bottom -> "Reached goal!"
            Stuck pat -> "Stuck: \n" <> unparseToString pat
            RewritePattern pat -> unparseToString pat

    indexNotFound :: String
    indexNotFound = "Variable or index not found"

    putStrLn' :: MonadIO m => String -> m ()
    putStrLn' = liftIO . putStrLn

    showDotGraph :: Graph gr => gr nl el -> IO ()
    showDotGraph =
        (flip Graph.runGraphvizCanvas') Graph.Xlib
            . Graph.graphToDot Graph.nonClusteredParams

data StepResult
    = NodeAlreadyEvaluated
    | NoChildNodes
    | Branch [Graph.Node]
    | Success
    deriving Show

unClaim :: forall level. Claim level -> RewriteRule level Kore.Variable
unClaim Claim { rule } = rule

unAxiom :: Axiom level -> RewriteRule level Kore.Variable
unAxiom (Axiom rule) = rule

emptyExecutionGraph
    :: Claim level
    -> Strategy.ExecutionGraph (CommonStrategyPattern level)
emptyExecutionGraph = Strategy.emptyExecutionGraph . extractConfig . unClaim

extractConfig
    :: RewriteRule level Kore.Variable
    -> CommonStrategyPattern level
extractConfig (RewriteRule RulePattern { left, requires }) =
    RewritePattern $ Predicated left requires mempty
