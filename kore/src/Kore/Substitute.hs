{-|
Module      : Kore.Substitute
Description : Abstract substitution algorithm
Copyright   : (c) Runtime Verification, 2019
License     : NCSA
Maintainer  : thomas.tuegel@runtimeverification.com
-}

module Kore.Substitute
    ( substitute
    ) where

import           Control.Comonad
import qualified Control.Lens as Lens
import qualified Data.Foldable as Foldable
import qualified Data.Functor.Foldable as Recursive
import           Data.Map.Strict
                 ( Map )
import qualified Data.Map.Strict as Map
import           Data.Set
                 ( Set )
import qualified Data.Set as Set

import Kore.Syntax
import Kore.Variables.Fresh

{- | Traverse the pattern from the top down and apply substitutions.

The 'freeVariables' annotation is used to avoid traversing subterms that
contain none of the targeted variables.

The substitution must be normalized, i.e. no target (left-hand side) variable
may appear in the right-hand side of any substitution, but this is not checked.

 -}
-- TODO (thomas.tuegel): In the future, patterns may have other types of
-- attributes which need to be re-synthesized after substitution.
substitute
    ::  forall domain variable attribute.
        ( FreshVariable variable
        , Ord variable
        , SortedVariable variable
        , Traversable domain
        )
    => Lens.Lens' attribute (Set variable)
    -- ^ Lens into free variables of the pattern
    -> Map variable (Pattern domain variable attribute)
    -- ^ Substitution
    -> Pattern domain variable attribute
    -- ^ Original pattern
    -> Pattern domain variable attribute
substitute lensFreeVariables = \subst -> substituteWorker (Map.map Right subst)
  where
    extractFreeVariables
        :: Pattern domain variable attribute
        -> Set variable
    extractFreeVariables = Lens.view lensFreeVariables . extract

    -- | Insert a variable renaming into the substitution.
    renaming
        :: variable  -- ^ Original variable
        -> variable  -- ^ Renamed variable
        -> Map variable (Either variable a)  -- ^ Substitution
        -> Map variable (Either variable a)
    renaming variable variable' = Map.insert variable (Left variable')

    substituteWorker subst termLike
      | Map.null subst' =
        -- If there are no targeted free variables, return the original pattern.
        -- Note that this covers the case of a non-targeted variable pattern,
        -- which produces an error below.
        termLike
      | otherwise =
        case termLikeHead of
            -- Capturing quantifiers
            ExistsF exists@Exists { existsVariable, existsChild }
              | Just existsVariable' <- avoidCapture existsVariable ->
                -- Rename the freshened bound variable in the subterms.
                let subst'' = renaming existsVariable existsVariable' subst'
                    exists' =
                        exists
                            { existsVariable = existsVariable'
                            , existsChild = substituteWorker subst'' existsChild
                            }
                in Recursive.embed (attrib' :< ExistsF exists')

            ForallF forall@Forall { forallVariable, forallChild }
              | Just forallVariable' <- avoidCapture forallVariable ->
                -- Rename the freshened bound variable in the subterms.
                let subst'' = renaming forallVariable forallVariable' subst'
                    forall' =
                        forall
                            { forallVariable = forallVariable'
                            , forallChild = substituteWorker subst'' forallChild
                            }
                in Recursive.embed (attrib' :< ForallF forall')

            -- Variables
            VariableF variable ->
                case Map.lookup variable subst' of
                    Nothing ->
                        -- This is impossible: if the pattern is a non-targeted
                        -- variable, we would have taken the first branch at
                        -- the top of substituteWorker.
                        error "Internal error: Impossible free variable"
                    Just (Left variable') ->
                        Recursive.embed (attrib' :< VariableF variable')
                    Just (Right termLike') ->
                        termLike'

            -- All other patterns
            _ ->
                let termLikeHead' =
                        substituteWorker subst' <$> termLikeHead
                in Recursive.embed (attrib' :< termLikeHead')
      where
        attrib :< termLikeHead = Recursive.project termLike
        freeVariables = Lens.view lensFreeVariables attrib
        attrib' = Lens.set lensFreeVariables freeVariables' attrib
        -- | The substitution applied to subterms, including only the free
        -- variables below the current node. Shadowed variables are
        -- automatically omitted.
        subst' = Map.intersection subst (Map.fromSet id freeVariables)
        -- | Free variables of the original pattern that are not targeted.
        originalVariables = Set.difference freeVariables (Map.keysSet subst')
        -- | Free variables of the resulting pattern.
        freeVariables' = Set.union originalVariables targetFreeVariables
          where
            -- | Free variables of the target substitutions.
            targetFreeVariables =
                Foldable.foldl'
                    Set.union
                    Set.empty
                    (either Set.singleton extractFreeVariables <$> subst')
        -- | Rename a bound variable, if needed.
        avoidCapture = refreshVariable freeVariables'

{-# INLINE substitute #-}
