module Test.Kore.Step.Simplification
    ( runSimplifier
    , runSimplifierSMT
    , runSimplifierBranch
    , simplifiedCondition
    , simplifiedOrCondition
    , simplifiedOrPattern
    , simplifiedPattern
    , simplifiedPredicate
    , simplifiedSubstitution
    , simplifiedTerm
    -- * Re-exports
    , Simplifier
    , SimplifierT
    , NoSMT
    , Env (..)
    , Kore.MonadSimplify
    ) where

import Prelude.Kore

import qualified Data.Functor.Foldable as Recursive

import qualified Kore.Attribute.Pattern as Attribute.Pattern
    ( fullySimplified
    , setSimplified
    )
import Kore.Internal.Condition
    ( Condition
    )
import Kore.Internal.Conditional
    ( Conditional (Conditional)
    )
import qualified Kore.Internal.Conditional as Conditional.DoNotUse
import Kore.Internal.OrCondition
    ( OrCondition
    )
import Kore.Internal.OrPattern
    ( OrPattern
    )
import qualified Kore.Internal.OrPattern as OrPattern
import Kore.Internal.Pattern
    ( Pattern
    )
import qualified Kore.Internal.Pattern as Pattern
    ( splitTerm
    , withCondition
    )
import Kore.Internal.Predicate
    ( Predicate
    )
import Kore.Internal.Substitution
    ( Substitution
    )
import qualified Kore.Internal.Substitution as Substitution
import Kore.Internal.TermLike
    ( TermLike
    )
import Kore.Internal.Variable
    ( InternalVariable
    )
import Kore.Step.Simplification.Data
    ( Env (..)
    , Simplifier
    , SimplifierT
    )
import qualified Kore.Step.Simplification.Data as Kore
import Kore.Step.SMT.Declaration.All as SMT.AST
import Logic
    ( LogicT
    )
import SMT
    ( NoSMT
    )
import qualified Test.Kore.Step.MockSymbols as Mock
import qualified Test.SMT as Test

runSimplifierSMT :: Env Simplifier -> Simplifier a -> IO a
runSimplifierSMT env = Test.runSMT userInit . Kore.runSimplifier env
  where
    userInit = SMT.AST.declare Mock.smtDeclarations

runSimplifier :: Env (SimplifierT NoSMT) -> SimplifierT NoSMT a -> IO a
runSimplifier env = Test.runNoSMT . Kore.runSimplifier env

runSimplifierBranch
    :: Env (SimplifierT NoSMT)
    -> LogicT (SimplifierT NoSMT) a
    -> IO [a]
runSimplifierBranch env = Test.runNoSMT . Kore.runSimplifierBranch env

simplifiedTerm :: TermLike variable -> TermLike variable
simplifiedTerm =
    Recursive.unfold (simplifiedWorker . Recursive.project)
  where
    simplifiedWorker (attrs :< patt) =
        Attribute.Pattern.setSimplified Attribute.Pattern.fullySimplified attrs
        :< patt

simplifiedPredicate :: Predicate variable -> Predicate variable
simplifiedPredicate = fmap simplifiedTerm

simplifiedSubstitution
    :: InternalVariable variable
    => Substitution variable
    -> Substitution variable
simplifiedSubstitution =
    Substitution.unsafeWrapFromAssignments
    . Substitution.unwrap
    . Substitution.mapTerms simplifiedTerm

simplifiedCondition
    :: InternalVariable variable
    => Condition variable
    -> Condition variable
simplifiedCondition Conditional { term = (), predicate, substitution } =
    Conditional
        { term = ()
        , predicate = simplifiedPredicate predicate
        , substitution = simplifiedSubstitution substitution
        }

simplifiedPattern
    :: InternalVariable variable
    => Pattern variable
    -> Pattern variable
simplifiedPattern patt =
    simplifiedTerm term `Pattern.withCondition` simplifiedCondition condition
  where
    (term, condition) = Pattern.splitTerm patt

simplifiedOrPattern
    :: InternalVariable variable
    => OrPattern variable
    -> OrPattern variable
simplifiedOrPattern = OrPattern.map simplifiedPattern

simplifiedOrCondition
    :: InternalVariable variable
    => OrCondition variable
    -> OrCondition variable
simplifiedOrCondition = OrPattern.map simplifiedCondition
