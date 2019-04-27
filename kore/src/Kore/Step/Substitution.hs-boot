module Kore.Step.Substitution where

import Kore.AST.Common
       ( SortedVariable )
import Kore.AST.MetaOrObject
import Kore.Attribute.Symbol
       ( StepperAttributes )
import Kore.IndexedModule.MetadataTools
       ( SmtMetadataTools )
import qualified Kore.Predicate.Predicate as Syntax
       ( Predicate )
import Kore.Step.Axiom.Data
       ( BuiltinAndAxiomSimplifierMap )
import Kore.Step.Pattern
       ( Predicate )
import Kore.Step.Simplification.Data
       ( PredicateSimplifier, StepPatternSimplifier )
import Kore.Unification.Data
       ( UnificationProof )
import Kore.Unification.Substitution
       ( Substitution )
import Kore.Unification.Unify
       ( MonadUnify )
import Kore.Unparser
import Kore.Variables.Fresh
       ( FreshVariable )

mergePredicatesAndSubstitutionsExcept
    ::  ( Show (variable level)
        , SortedVariable variable
        , MetaOrObject level
        , Ord (variable level)
        , Unparse (variable level)
        , OrdMetaOrObject variable
        , ShowMetaOrObject variable
        , FreshVariable variable
        , MonadUnify unifierM
        , unifier ~ unifierM variable
        )
    => SmtMetadataTools StepperAttributes
    -> PredicateSimplifier level
    -> StepPatternSimplifier level
    -> BuiltinAndAxiomSimplifierMap level
    -> [Syntax.Predicate variable]
    -> [Substitution variable]
    -> unifier
        ( Predicate level variable
        , UnificationProof level variable
        )
