{- |
Copyright   : (c) Runtime Verification, 2019
License     : NCSA

Target specific variables for unification.

 -}

module Kore.Variables.Target
    ( Target (..)
    , unTarget
    , unTargetElement
    , unTargetSet
    , mkElementTarget
    , mkSetTarget
    , mkUnifiedTarget
    , isTarget
    , mkElementNonTarget
    , mkSetNonTarget
    , mkUnifiedNonTarget
    , isNonTarget
    , targetIfEqual
    ) where

import Prelude.Kore

import qualified Control.Lens as Lens
import qualified Generics.SOP as SOP
import qualified GHC.Generics as GHC

import Kore.Debug
import Kore.Internal.Variable
import Kore.Syntax.Variable
    ( NamedVariable (..)
    , SortedVariable (..)
    )
import Kore.Unparser
    ( Unparse (..)
    )
import Kore.Variables.Fresh
    ( FreshPartialOrd (..)
    , FreshVariable (..)
    )

{- | Distinguish variables by their source.

'Target' variables always compare 'LT' 'NonTarget' variables under
'SubstitutionOrd', so that the unification procedure prefers to generate
substitutions for 'Target' variables instead of 'NonTarget' variables.

 -}
data Target variable
    = Target !variable
    | NonTarget !variable
    deriving (GHC.Generic, Show)
    deriving (Functor, Foldable, Traversable)

instance Eq variable => Eq (Target variable) where
    (==) a b = unTarget a == unTarget b
    {-# INLINE (==) #-}

instance Ord variable => Ord (Target variable) where
    compare a b = compare (unTarget a) (unTarget b)
    {-# INLINE compare #-}

instance Hashable variable => Hashable (Target variable) where
    hashWithSalt salt target = hashWithSalt salt (unTarget target)
    {-# INLINE hashWithSalt #-}

instance SOP.Generic (Target variable)

instance SOP.HasDatatypeInfo (Target variable)

instance Debug variable => Debug (Target variable)

instance (Debug variable, Diff variable) => Diff (Target variable)

{- | Prefer substitutions for 'isTarget' variables.
 -}
instance
    SubstitutionOrd variable => SubstitutionOrd (Target variable)
  where
    compareSubstitution (Target _) (NonTarget _) = LT
    compareSubstitution (NonTarget _) (Target _) = GT
    compareSubstitution variable1 variable2 =
        on compareSubstitution unTarget variable1 variable2

unTarget :: Target variable -> variable
unTarget (Target variable) = variable
unTarget (NonTarget variable) = variable
{-# INLINE unTarget #-}

unTargetElement :: ElementVariable (Target variable) -> ElementVariable variable
unTargetElement = fmap unTarget

unTargetSet :: SetVariable (Target variable) -> SetVariable variable
unTargetSet = fmap unTarget

mkElementTarget
    :: ElementVariable variable
    -> ElementVariable (Target variable)
mkElementTarget = fmap Target

mkSetTarget
    :: SetVariable variable
    -> SetVariable (Target variable)
mkSetTarget = fmap Target

mkUnifiedTarget :: AdjSomeVariableName (variable -> Target variable)
mkUnifiedTarget = pure Target

isTarget :: Target variable -> Bool
isTarget (Target _) = True
isTarget (NonTarget _) = False

mkElementNonTarget
    :: ElementVariable variable
    -> ElementVariable (Target variable)
mkElementNonTarget = fmap NonTarget

mkSetNonTarget
    :: SetVariable variable
    -> SetVariable (Target variable)
mkSetNonTarget = fmap NonTarget

mkUnifiedNonTarget :: AdjSomeVariableName (variable -> Target variable)
mkUnifiedNonTarget = pure NonTarget

isNonTarget :: Target variable -> Bool
isNonTarget = not . isTarget

instance
    SortedVariable variable
    => SortedVariable (Target variable)
  where
    lensVariableSort f =
        \case
            Target variable -> Target <$> lensVariableSort f variable
            NonTarget variable -> Target <$> lensVariableSort f variable
    {-# INLINE lensVariableSort #-}

instance NamedVariable variable => NamedVariable (Target variable) where
    type VariableNameOf (Target variable) = Target (VariableNameOf variable)

    isoVariable1 =
        Lens.iso to fr
      where
        to (Target variable) = Target <$> Lens.view isoVariable1 variable
        to (NonTarget variable) = NonTarget <$> Lens.view isoVariable1 variable
        fr Variable1 { variableName1, variableSort1 } =
            flip fmap variableName1 $ \variableName1' ->
                Variable1
                { variableName1 = variableName1'
                , variableSort1
                }
                & Lens.review isoVariable1

instance VariableBase variable => VariableBase (Target variable)

instance From variable1 variable2 => From variable1 (Target variable2) where
    from = Target . from @variable1 @variable2
    {-# INLINE from #-}

instance From variable1 variable2 => From (Target variable1) variable2 where
    from = from @variable1 @variable2 . unTarget
    {-# INLINE from #-}

instance FreshPartialOrd variable => FreshPartialOrd (Target variable) where
    infVariable =
        \case
            Target var    -> Target (infVariable var)
            NonTarget var -> NonTarget (infVariable var)
    {-# INLINE infVariable #-}

    supVariable =
        \case
            Target var    -> Target (supVariable var)
            NonTarget var -> NonTarget (supVariable var)
    {-# INLINE supVariable #-}

    nextVariable =
        \case
            Target var    -> Target (nextVariable var)
            NonTarget var -> NonTarget (nextVariable var)
    {-# INLINE nextVariable #-}

{- | Ensures that fresh variables are unique under 'unwrapStepperVariable'.
 -}
instance
    (FreshPartialOrd variable, SortedVariable variable)
    => FreshVariable (Target variable)

instance
    Unparse variable =>
    Unparse (Target variable)
  where
    unparse (Target var) = unparse var
    unparse (NonTarget var) = unparse var
    unparse2 (Target var) = unparse2 var
    unparse2 (NonTarget var) = unparse2 var

targetIfEqual
    :: NamedVariable variable
    => ElementVariable variable
    -> VariableNameOf variable
    -> VariableNameOf (Target variable)
targetIfEqual boundVariable variableName =
    if boundVariableName == variableName
        then Target variableName
        else NonTarget variableName
  where
    boundVariableName =
        Lens.view lensVariableName boundVariable
        & unElementVariableName
