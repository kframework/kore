{-|
Module      : Kore.Unification.UnifierImpl
Description : Datastructures and functionality for performing unification on
              Pure patterns
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : traian.serbanuta@runtimeverification.com
Stability   : experimental
Portability : portable
-}
module Kore.Unification.UnifierImpl where

import qualified Control.Comonad.Trans.Cofree as Cofree
import           Control.Monad
                 ( foldM )
import           Data.Function
                 ( on )
import qualified Data.Functor.Foldable as Recursive
import           Data.List
                 ( foldl', groupBy, partition, sortBy )
import           Data.List.NonEmpty
                 ( NonEmpty (..) )

import           Kore.AST.Pure
import           Kore.Attribute.Symbol
import           Kore.IndexedModule.MetadataTools
import qualified Kore.Predicate.Predicate as Predicate
                 ( isFalse, makeAndPredicate, makeTruePredicate )
import           Kore.Step.Axiom.Data
                 ( BuiltinAndAxiomSimplifierMap )
import qualified Kore.Step.Conditional as Predicated
import           Kore.Step.Representation.ExpandedPattern
                 ( ExpandedPattern )
import qualified Kore.Step.Representation.ExpandedPattern as ExpandedPattern
import           Kore.Step.Representation.PredicateSubstitution
                 ( PredicateSubstitution, Predicated (..) )
import qualified Kore.Step.Representation.PredicateSubstitution as PredicateSubstitution
import           Kore.Step.Simplification.Data
                 ( PredicateSubstitutionSimplifier (..),
                 StepPatternSimplifier )
import           Kore.Step.TermLike
                 ( TermLike )
import           Kore.Unification.Data
import           Kore.Unification.Substitution
                 ( Substitution )
import qualified Kore.Unification.Substitution as Substitution
import           Kore.Unification.Unify
                 ( MonadUnify )
import           Kore.Unparser
import           Kore.Variables.Fresh
                 ( FreshVariable )

import {-# SOURCE #-} Kore.Step.Simplification.AndTerms
       ( termUnification )
import {-# SOURCE #-} Kore.Step.Substitution
       ( mergePredicatesAndSubstitutionsExcept )

simplifyUnificationProof
    :: UnificationProof Object variable
    -> UnificationProof Object variable
simplifyUnificationProof EmptyUnificationProof = EmptyUnificationProof
simplifyUnificationProof (CombinedUnificationProof []) =
    EmptyUnificationProof
simplifyUnificationProof (CombinedUnificationProof [a]) =
    simplifyUnificationProof a
simplifyUnificationProof (CombinedUnificationProof items) =
    case simplifyCombinedItems items of
        []  -> EmptyUnificationProof
        [a] -> a
        as  -> CombinedUnificationProof as
simplifyUnificationProof a@(ConjunctionIdempotency _) = a
simplifyUnificationProof a@(Proposition_5_24_3 _ _ _) = a
simplifyUnificationProof
    (AndDistributionAndConstraintLifting symbolOrAlias unificationProof)
  =
    AndDistributionAndConstraintLifting
        symbolOrAlias
        (simplifyCombinedItems unificationProof)
simplifyUnificationProof a@(SubstitutionMerge _ _ _) = a

simplifyCombinedItems
    :: [UnificationProof Object variable] -> [UnificationProof Object variable]
simplifyCombinedItems =
    foldr (addContents . simplifyUnificationProof) []
  where
    addContents
        :: UnificationProof Object variable
        -> [UnificationProof Object variable]
        -> [UnificationProof Object variable]
    addContents EmptyUnificationProof  proofItems           = proofItems
    addContents (CombinedUnificationProof items) proofItems =
        items ++ proofItems
    addContents other proofItems = other : proofItems

simplifyAnds
    ::  forall variable unifier unifierM .
        ( MetaOrObject Object
        , Eq Object
        , Ord (variable Object)
        , Show (variable Object)
        , Unparse (variable Object)
        , OrdMetaOrObject variable
        , ShowMetaOrObject variable
        , SortedVariable variable
        , FreshVariable variable
        , unifier ~ unifierM variable
        , MonadUnify unifierM
        )
    => SmtMetadataTools StepperAttributes
    -> PredicateSubstitutionSimplifier Object
    -> StepPatternSimplifier Object
    -> BuiltinAndAxiomSimplifierMap Object
    -> NonEmpty (TermLike variable)
    -> unifier (ExpandedPattern Object variable, UnificationProof Object variable)
simplifyAnds
    tools
    substitutionSimplifier
    simplifier
    axiomIdToSimplifier
    patterns
  = do
    result <- foldM simplifyAnds' ExpandedPattern.top patterns
    if Predicate.isFalse . ExpandedPattern.predicate $ result
        then return ( ExpandedPattern.bottom, EmptyUnificationProof )
        else return ( result, EmptyUnificationProof )
  where
    simplifyAnds'
        :: ExpandedPattern Object variable
        -> TermLike variable
        -> unifier (ExpandedPattern Object variable)
    simplifyAnds' intermediate pat =
        case Cofree.tailF (Recursive.project pat) of
            AndPattern And { andFirst = lhs, andSecond = rhs } ->
                foldM simplifyAnds' intermediate [lhs, rhs]
            _ -> do
                (result, _) <-
                    termUnification
                        tools
                        substitutionSimplifier
                        simplifier
                        axiomIdToSimplifier
                        (ExpandedPattern.term intermediate)
                        pat
                (predSubst, _) <-
                    mergePredicatesAndSubstitutionsExcept
                        tools
                        substitutionSimplifier
                        simplifier
                        axiomIdToSimplifier
                        [ ExpandedPattern.predicate result
                        , ExpandedPattern.predicate intermediate
                        ]
                        [ ExpandedPattern.substitution result
                        , ExpandedPattern.substitution intermediate
                        ]
                return ExpandedPattern.Predicated
                    { term = ExpandedPattern.term result
                    , predicate = Predicated.predicate predSubst
                    , substitution = Predicated.substitution predSubst
                    }


groupSubstitutionByVariable
    :: Ord (variable Object)
    => [(variable Object, TermLike variable)]
    -> [[(variable Object, TermLike variable)]]
groupSubstitutionByVariable =
    groupBy ((==) `on` fst) . sortBy (compare `on` fst) . map sortRenaming
  where
    sortRenaming (var, Recursive.project -> ann :< VariablePattern var')
        | var' < var =
          (var', Recursive.embed (ann :< VariablePattern var))
    sortRenaming eq = eq

-- simplifies x = t1 /\ x = t2 /\ ... /\ x = tn by transforming it into
-- x = ((t1 /\ t2) /\ (..)) /\ tn
-- then recursively reducing that to finally get x = t /\ subst
solveGroupedSubstitution
    :: ( MetaOrObject Object
       , Eq Object
       , Ord (variable Object)
       , Show (variable Object)
       , Unparse (variable Object)
       , OrdMetaOrObject variable
       , ShowMetaOrObject variable
       , SortedVariable variable
       , FreshVariable variable
       , MonadUnify unifierM
       , unifier ~ unifierM variable
      )
    => SmtMetadataTools StepperAttributes
    -> PredicateSubstitutionSimplifier Object
    -> StepPatternSimplifier Object
    -> BuiltinAndAxiomSimplifierMap Object
    -> variable Object
    -> NonEmpty (TermLike variable)
    -> unifier
        ( PredicateSubstitution Object variable
        , UnificationProof Object variable
        )
solveGroupedSubstitution
    tools
    substitutionSimplifier
    simplifier
    axiomIdToSimplifier
    var
    patterns
  = do
    (predSubst, proof) <-
        simplifyAnds
            tools
            substitutionSimplifier
            simplifier
            axiomIdToSimplifier
            patterns
    return
        ( Predicated
            { term = ()
            , predicate = ExpandedPattern.predicate predSubst
            , substitution = Substitution.wrap $ termAndSubstitution predSubst
            }
        , proof
        )
  where
    termAndSubstitution s =
        (var, ExpandedPattern.term s)
        : Substitution.unwrap (ExpandedPattern.substitution s)

-- |Takes a potentially non-normalized substitution,
-- and if it contains multiple assignments to the same variable,
-- it solves all such assignments.
-- As new assignments may be produced during the solving process,
-- `normalizeSubstitutionDuplication` recursively calls itself until it
-- stabilizes.
normalizeSubstitutionDuplication
    :: forall variable unifier unifierM
    .   ( MetaOrObject Object
        , Eq Object
        , Ord (variable Object)
        , Show (variable Object)
        , Unparse (variable Object)
        , OrdMetaOrObject variable
        , ShowMetaOrObject variable
        , SortedVariable variable
        , FreshVariable variable
        , MonadUnify unifierM
        , unifier ~ unifierM variable
        )
    => SmtMetadataTools StepperAttributes
    -> PredicateSubstitutionSimplifier Object
    -> StepPatternSimplifier Object
    -> BuiltinAndAxiomSimplifierMap Object
    -> Substitution variable
    -> unifier
        ( PredicateSubstitution Object variable
        , UnificationProof Object variable
        )
normalizeSubstitutionDuplication
    tools
    substitutionSimplifier
    simplifier
    axiomIdToSimplifier
    subst
  =
    if null nonSingletonSubstitutions || Substitution.isNormalized subst
        then return
            ( Predicated () Predicate.makeTruePredicate subst
            , EmptyUnificationProof
            )
        else do
            (predSubst, proof') <-
                mergePredicateSubstitutionList
                <$> mapM
                    (uncurry
                        $ solveGroupedSubstitution
                            tools
                            substitutionSimplifier
                            simplifier
                            axiomIdToSimplifier
                    )
                    varAndSubstList
            (finalSubst, proof) <-
                normalizeSubstitutionDuplication
                    tools
                    substitutionSimplifier
                    simplifier
                    axiomIdToSimplifier
                    (  Substitution.wrap (concat singletonSubstitutions)
                    <> Predicated.substitution predSubst
                    )
            let
                pred' =
                    Predicate.makeAndPredicate
                        (Predicated.predicate predSubst)
                        (Predicated.predicate finalSubst)
            return
                ( Predicated
                    { term = ()
                    , predicate = pred'
                    , substitution = Predicated.substitution finalSubst
                    }
                , CombinedUnificationProof
                    [ proof'
                    , proof
                    ]
                )
  where
    groupedSubstitution = groupSubstitutionByVariable $ Substitution.unwrap subst
    isSingleton [_] = True
    isSingleton _   = False
    singletonSubstitutions, nonSingletonSubstitutions
        :: [[(variable Object, TermLike variable)]]
    (singletonSubstitutions, nonSingletonSubstitutions) =
        partition isSingleton groupedSubstitution
    varAndSubstList :: [(variable Object, NonEmpty (TermLike variable))]
    varAndSubstList =
        nonSingletonSubstitutions >>= \case
            [] -> []
            ((x, y) : ys) -> [(x, y :| (snd <$> ys))]


mergePredicateSubstitutionList
    :: ( MetaOrObject Object
       , Eq Object
       , Ord (variable Object)
       , OrdMetaOrObject variable
       , SortedVariable variable
       , Show (variable Object)
       , Unparse (variable Object)
       )
    => [(PredicateSubstitution Object variable, UnificationProof Object variable)]
    -> (PredicateSubstitution Object variable, UnificationProof Object variable)
mergePredicateSubstitutionList [] =
    ( PredicateSubstitution.top
    , EmptyUnificationProof
    )
mergePredicateSubstitutionList (p:ps) =
    foldl' mergePredicateSubstitutions p ps
  where
    mergePredicateSubstitutions
        ( Predicated { predicate = p1, substitution = s1 }, proofs)
        ( Predicated { predicate = p2, substitution = s2 }, proof) =
        ( Predicated
            { term = ()
            , predicate = Predicate.makeAndPredicate p1 p2
            , substitution = s1 <> s2
            }
        , proofs <> proof
        )
