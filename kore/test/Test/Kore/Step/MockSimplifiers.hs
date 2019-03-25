module Test.Kore.Step.MockSimplifiers where

import qualified Data.Map as Map

import           Kore.AST.Valid
import           Kore.Attribute.Symbol
                 ( StepperAttributes )
import           Kore.IndexedModule.MetadataTools
                 ( MetadataTools )
import qualified Kore.Predicate.Predicate as Predicate
                 ( wrapPredicate )
import           Kore.Step.Representation.ExpandedPattern
                 ( Predicated (Predicated) )
import qualified Kore.Step.Representation.ExpandedPattern as ExpandedPattern
                 ( Predicated (..) )
import qualified Kore.Step.Representation.MultiOr as MultiOr
                 ( make )
import           Kore.Step.Simplification.Data
                 ( PredicateSubstitutionSimplifier (..),
                 SimplificationProof (SimplificationProof),
                 StepPatternSimplifier (StepPatternSimplifier) )
import qualified Kore.Step.Simplification.PredicateSubstitution as PredicateSubstitution
                 ( create )

substitutionSimplifier
    :: MetadataTools level StepperAttributes
    -> PredicateSubstitutionSimplifier level
substitutionSimplifier tools =
    PredicateSubstitution.create
        tools
        (StepPatternSimplifier
            (\_ p ->
                return
                    ( MultiOr.make
                        [ Predicated
                            { term = mkTop_
                            , predicate = Predicate.wrapPredicate p
                            , substitution = mempty
                            }
                        ]
                    , SimplificationProof
                    )
            )
        )
        Map.empty
