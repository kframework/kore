{-|
Copyright   : (c) Runtime Verification, 2020
License     : NCSA
-}

-- For instance Applicative:
{-# LANGUAGE UndecidableInstances #-}

module Kore.Internal.SideCondition
    ( SideCondition  -- Constructor not exported on purpose
    , fromCondition
    , fromPredicate
    , andCondition
    , assumeTrueCondition
    , assumeTruePredicate
    , mapVariables
    , top
    , topTODO
    , toPredicate
    , isNormalized
    ) where

import Prelude.Kore

import Control.DeepSeq
    ( NFData
    )
import qualified Generics.SOP as SOP
import qualified GHC.Generics as GHC

import Debug
import Kore.Attribute.Pattern.FreeVariables
    ( HasFreeVariables (..)
    )
import Kore.Internal.Condition
    ( Condition
    )
import qualified Kore.Internal.Condition as Condition
import qualified Kore.Internal.Conditional as Conditional
import Kore.Internal.Predicate
    ( Predicate
    )
-- import Kore.Internal.SideCondition.SideCondition as SideCondition
import Kore.Internal.Variable
    ( InternalVariable
    , SubstitutionOrd
    )
import Kore.Syntax.Variable
import Kore.TopBottom
    ( TopBottom (..)
    )
import Kore.Unparser
    ( Unparse (..)
    )
import qualified Pretty
import qualified SQL

{-| Side condition used in the evaluation context.

It is not added to the result.

It is usually used to remove infeasible branches, but it may also be used for
other purposes, say, to remove redundant parts of the result predicate.
-}
newtype SideCondition variable =
    SideCondition
        { assumedTrue :: Condition variable
        }
    deriving (Eq, Ord, Show)
    deriving (GHC.Generic)
    deriving anyclass (Hashable, NFData)
    deriving anyclass (SOP.Generic, SOP.HasDatatypeInfo)
    deriving anyclass (Debug)

instance
    (Debug variable, Diff variable, Ord variable, SubstitutionOrd variable)
    => Diff (SideCondition variable)

instance InternalVariable variable => SQL.Column (SideCondition variable) where
    defineColumn = SQL.defineTextColumn
    toColumn = SQL.toColumn . Pretty.renderText . Pretty.layoutOneLine . unparse

instance TopBottom (SideCondition variable) where
    isTop sideCondition@(SideCondition _) =
        isTop assumedTrue
      where
        SideCondition {assumedTrue} = sideCondition
    isBottom sideCondition@(SideCondition _) =
        isBottom assumedTrue
      where
        SideCondition {assumedTrue} = sideCondition

instance InternalVariable variable
    => HasFreeVariables (SideCondition variable) variable
  where
    freeVariables sideCondition@(SideCondition _) =
        freeVariables assumedTrue
      where
        SideCondition {assumedTrue} = sideCondition

instance InternalVariable variable => Unparse (SideCondition variable) where
    unparse sideCondition@(SideCondition _) =
        unparse assumedTrue
      where
        SideCondition {assumedTrue} = sideCondition

    unparse2 sideCondition@(SideCondition _) =
        unparse2 assumedTrue
      where
        SideCondition {assumedTrue} = sideCondition

instance From (Condition variable) (SideCondition variable)
  where
      from = SideCondition

instance From (SideCondition variable) (Condition variable) where
    from = assumedTrue
    {-# INLINE from #-}

instance
    InternalVariable variable
    => From (SideCondition variable) (Predicate variable)
  where
    from = from @(Condition variable) . from @(SideCondition variable)
    {-# INLINE from #-}

instance
    InternalVariable variable
    => From (Predicate variable) (SideCondition variable)
  where
    from = from @(Condition variable) . from @(Predicate variable)
    {-# INLINE from #-}

top :: InternalVariable variable => SideCondition variable
top = fromCondition Condition.top

-- | A 'top' 'Condition' for refactoring which should eventually be removed.
topTODO :: InternalVariable variable => SideCondition variable
topTODO = top

andCondition
    :: InternalVariable variable
    => SideCondition variable
    -> Condition variable
    -> SideCondition variable
andCondition SideCondition { assumedTrue } newCondition =
    SideCondition merged
  where
    merged = assumedTrue `Condition.andCondition` newCondition

assumeTrueCondition :: Condition variable -> SideCondition variable
assumeTrueCondition = fromCondition

assumeTruePredicate
    :: InternalVariable variable => Predicate variable -> SideCondition variable
assumeTruePredicate predicate =
    assumeTrueCondition (Condition.fromPredicate predicate)

toPredicate
    :: InternalVariable variable
    => SideCondition variable
    -> Predicate variable
toPredicate condition@(SideCondition _) =
    Condition.toPredicate assumedTrue
  where
    SideCondition { assumedTrue } = condition

mapVariables
    :: (InternalVariable variable1, InternalVariable variable2)
    => AdjSomeVariableName (variable1 -> variable2)
    -> SideCondition variable1
    -> SideCondition variable2
mapVariables adj condition@(SideCondition _) =
    fromCondition (Condition.mapVariables adj assumedTrue)
  where
    SideCondition { assumedTrue } = condition

fromCondition :: Condition variable -> SideCondition variable
fromCondition = from

fromPredicate
    :: InternalVariable variable => Predicate variable -> SideCondition variable
fromPredicate = fromCondition . from

-- toRepresentationCondition
--     :: InternalVariable variable
--     => Condition variable
--     -> SideCondition.Representation
-- toRepresentationCondition =
--     mkRepresentation
--     . Condition.mapVariables @_ @VariableName (pure toVariableName)

isNormalized :: forall variable. Ord variable => SideCondition variable -> Bool
isNormalized = Conditional.isNormalized . from @_ @(Condition variable)
