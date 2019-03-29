module Kore.Step.Substitution where

import Control.Monad.Except
       ( ExceptT )

import Kore.AST.Common
       ( SortedVariable )
import Kore.AST.MetaOrObject
import Kore.Attribute.Symbol
       ( StepperAttributes )
import Kore.IndexedModule.MetadataTools
       ( MetadataTools )
import Kore.Predicate.Predicate
       ( Predicate )
import Kore.Step.Axiom.Data
       ( BuiltinAndAxiomSimplifierMap )
import Kore.Step.Representation.ExpandedPattern
       ( PredicateSubstitution )
import Kore.Step.Simplification.Data
       ( PredicateSubstitutionSimplifier, Simplifier, StepPatternSimplifier )
import Kore.Unification.Data
       ( UnificationProof )
import Kore.Unification.Error
       ( UnificationOrSubstitutionError )
import Kore.Unification.Substitution
       ( Substitution )
import Kore.Unparser
import Kore.Variables.Fresh
       ( FreshVariable )

mergePredicatesAndSubstitutionsExcept
    :: ( Show (variable level)
       , SortedVariable variable
       , MetaOrObject level
       , Ord (variable level)
       , Unparse (variable level)
       , OrdMetaOrObject variable
       , ShowMetaOrObject variable
       , FreshVariable variable
       )
    => MetadataTools level StepperAttributes
    -> PredicateSubstitutionSimplifier level
    -> StepPatternSimplifier level
    -> BuiltinAndAxiomSimplifierMap level
    -> [Predicate level variable]
    -> [Substitution level variable]
    -> ExceptT
        ( UnificationOrSubstitutionError level variable )
        Simplifier
        ( PredicateSubstitution level variable
        , UnificationProof level variable
        )
