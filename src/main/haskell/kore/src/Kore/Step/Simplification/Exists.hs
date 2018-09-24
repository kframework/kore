{-|
Module      : Kore.Step.Simplification.Exists
Description : Tools for Exists pattern simplification.
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : virgil.serbanuta@runtimeverification.com
Stability   : experimental
Portability : portable
-}
module Kore.Step.Simplification.Exists
    ( simplify
    , makeEvaluate
    ) where

import qualified Control.Arrow as Arrow
import           Data.Proxy
                 ( Proxy (..) )
import           Data.Reflection
import qualified Data.Set as Set

import           Kore.AST.Common
import           Kore.AST.MetaOrObject
import           Kore.AST.PureML
                 ( PureMLPattern )
import           Kore.ASTUtils.SmartConstructors
                 ( mkExists )
import           Kore.IndexedModule.MetadataTools
                 ( MetadataTools, SortTools )
import           Kore.Predicate.Predicate
                 ( Predicate, makeExistsPredicate, makeTruePredicate,
                 unwrapPredicate )
import           Kore.Step.ExpandedPattern
                 ( ExpandedPattern (ExpandedPattern) )
import qualified Kore.Step.ExpandedPattern as ExpandedPattern
                 ( ExpandedPattern (..), toMLPattern )
import           Kore.Step.OrOfExpandedPattern
                 ( OrOfExpandedPattern )
import qualified Kore.Step.OrOfExpandedPattern as OrOfExpandedPattern
                 ( isFalse, isTrue, make, traverseFlattenWithPairs )
import           Kore.Step.Simplification.Data
                 ( PureMLPatternSimplifier (..), SimplificationProof (..),
                 Simplifier )
import qualified Kore.Step.Simplification.ExpandedPattern as ExpandedPattern
                 ( simplify )
import           Kore.Step.StepperAttributes
import           Kore.Substitution.Class
import qualified Kore.Substitution.List as ListSubstitution
import           Kore.Unification.Unifier
                 ( UnificationSubstitution )
import           Kore.Variables.Free
                 ( pureFreeVariables )
import Kore.SMT.SMT

-- TODO: Move Exists up in the other simplifiers or something similar. Note
-- that it messes up top/bottom testing so moving it up must be done
-- immediately after evaluating the children.
{-|'simplify' simplifies an 'Exists' pattern with an 'OrOfExpandedPattern'
child.

The simplification of exists x . (pat and pred and subst) is equivalent to:

* If the subst contains an assignment for x, then substitute that in pat and
  pred, reevaluate them and return
  (reevaluated-pat and reevaluated-pred and subst-without-x).
* Otherwise, if x does not occur free in pat and pred, return
  (pat and pred and subst)
* Otherwise, if x does not occur free in pat, return
  (pat and (exists x . pred) and subst)
* Otherwise, if x does not occur free in pred, return
  ((exists x . pat) and pred and subst)
* Otherwise return
  ((exists x . pat and pred) and subst)
-}
simplify
    ::  ( MetaOrObject level
        , Given (SortTools level)
        )
    => MetadataTools level StepperAttributes
    -> PureMLPatternSimplifier level Variable
    -- ^ Simplifies patterns.
    -> Exists level Variable (OrOfExpandedPattern level Variable)
    -> Simplifier
        ( OrOfExpandedPattern level Variable
        , SimplificationProof level
        )
simplify
    tools
    simplifier
    Exists { existsVariable = variable, existsChild = child }
  = give (convertMetadataTools tools) $ 
      simplifyEvaluated tools simplifier variable child

simplifyEvaluated
    ::  ( MetaOrObject level
        , Given (MetadataTools level SMTAttributes)
        , Given (SortTools level)
        )
    => MetadataTools level StepperAttributes
    -> PureMLPatternSimplifier level Variable
    -- ^ Simplifies patterns.
    -> Variable level
    -> OrOfExpandedPattern level Variable
    -> Simplifier
        (OrOfExpandedPattern level Variable, SimplificationProof level)
simplifyEvaluated tools simplifier variable simplified
  | OrOfExpandedPattern.isTrue simplified =
    return (simplified, SimplificationProof)
  | OrOfExpandedPattern.isFalse simplified =
    return (simplified, SimplificationProof)
  | otherwise = do
    (evaluated, _proofs) <-
        OrOfExpandedPattern.traverseFlattenWithPairs
            (makeEvaluate tools simplifier variable) simplified
    return ( evaluated, SimplificationProof )

{-| evaluates an 'Exists' given its two 'ExpandedPattern' children.

See 'simplify' for detailed documentation.
-}
makeEvaluate
    ::  ( MetaOrObject level
        , Given (MetadataTools level SMTAttributes)
        , Given (SortTools level)
        )
    => MetadataTools level StepperAttributes
    -> PureMLPatternSimplifier level Variable
    -- ^ Simplifies patterns.
    -> Variable level
    -> ExpandedPattern level Variable
    -> Simplifier
        (OrOfExpandedPattern level Variable, SimplificationProof level)
makeEvaluate
    tools
    simplifier
    variable
    patt@ExpandedPattern { term, predicate, substitution }
  = give (convertMetadataTools tools) $ 
    case localSubstitution of
        [] ->
            return (makeEvaluateNoFreeVarInSubstitution variable patt)
        _ -> do
            (substitutedPat, _proof) <-
                substituteTermPredicate
                    term
                    predicate
                    localSubstitutionList
                    globalSubstitution
            (result, _proof) <-
                ExpandedPattern.simplify tools simplifier substitutedPat
            return (result , SimplificationProof)
  where
    (Local localSubstitution, Global globalSubstitution) =
        splitSubstitutionByVariable variable substitution
    localSubstitutionList =
        ListSubstitution.fromList
            (map (Arrow.first asUnified) localSubstitution)

makeEvaluateNoFreeVarInSubstitution
    ::  ( MetaOrObject level
        , Given (MetadataTools level SMTAttributes)
        , Given (SortTools level)
        )
    => Variable level
    -> ExpandedPattern level Variable
    -> (OrOfExpandedPattern level Variable, SimplificationProof level)
makeEvaluateNoFreeVarInSubstitution
    variable
    patt@ExpandedPattern { term, predicate, substitution }
  =
    (OrOfExpandedPattern.make [simplifiedPattern], SimplificationProof)
  where
    termHasVariable =
        variable
            `Set.member`
            pureFreeVariables (Proxy :: Proxy level) term
    predicateHasVariable =
        variable
            `Set.member`
            pureFreeVariables
                (Proxy :: Proxy level)
                (unwrapPredicate predicate)
    simplifiedPattern = case (termHasVariable, predicateHasVariable) of
        (False, False) -> patt
        (False, True) ->
            let
                (predicate', _proof) =
                    makeExistsPredicate variable predicate
            in
                ExpandedPattern
                    { term = term
                    , predicate = predicate'
                    , substitution = substitution
                    }
        (True, False) ->
            ExpandedPattern
                { term = mkExists variable term
                , predicate = predicate
                , substitution = substitution
                }
        (True, True) ->
            ExpandedPattern
                { term =
                    mkExists variable
                        (ExpandedPattern.toMLPattern
                            ExpandedPattern
                                { term = term
                                , predicate = predicate
                                , substitution = []
                                }
                        )
                , predicate = makeTruePredicate
                , substitution = substitution
                }

substituteTermPredicate
    ::  ( MetaOrObject level
        , Given (MetadataTools level SMTAttributes)
        , Given (SortTools level)
        )
    => PureMLPattern level Variable
    -> Predicate level Variable
    -> ListSubstitution.Substitution (Unified Variable) (PureMLPattern level Variable)
    -> UnificationSubstitution level Variable
    -> Simplifier
        (ExpandedPattern level Variable, SimplificationProof level)
substituteTermPredicate term predicate substitution globalSubstitution = do
    substitutedTerm <- substitute term substitution
    substitutedPredicate <-
        traverse (`substitute` substitution) predicate
    return
        ( ExpandedPattern
            { term = substitutedTerm
            , predicate = substitutedPredicate
            , substitution = globalSubstitution
            }
        , SimplificationProof
        )

newtype Local a = Local a
newtype Global a = Global a

splitSubstitutionByVariable
    :: Eq (Variable level)
    => Variable level
    -> UnificationSubstitution level Variable
    ->  ( Local (UnificationSubstitution level Variable)
        , Global (UnificationSubstitution level Variable)
        )
splitSubstitutionByVariable _ [] =
    (Local [], Global [])
splitSubstitutionByVariable variable ((var, term) : substs)
  | var == variable =
    (Local [(var, term)], Global substs)
  | otherwise =
    (local, Global ((var, term) : global))
  where
    (local, Global global) = splitSubstitutionByVariable variable substs
