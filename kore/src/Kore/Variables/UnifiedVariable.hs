{-|
Copyright   : (c) Runtime Verification, 2019
License     : NCSA

-}
module Kore.Variables.UnifiedVariable
    ( UnifiedVariable (..)
    , isElemVar
    , expectElemVar
    , isSetVar
    , expectSetVar
    , extractElementVariable
    , foldMapVariable
    , unifiedVariableSort
    , refreshElementVariable
    , refreshSetVariable
    ) where

import Prelude.Kore

import Control.DeepSeq
    ( NFData
    )
import Data.Functor.Const
import Data.Hashable
import Data.Set
    ( Set
    )
import qualified Data.Set as Set
import qualified Generics.SOP as SOP
import GHC.Generics
    ( Generic
    )

import Kore.Attribute.Synthetic
import Kore.Debug
import Kore.Sort
import Kore.Syntax.ElementVariable
import Kore.Syntax.SetVariable
import Kore.Syntax.Variable
    ( SortedVariable (..)
    )
import Kore.Unparser
import Kore.Variables.Fresh

{- | @UnifiedVariable@ helps distinguish set variables (introduced by 'SetVar')
from element variables (introduced by 'ElemVar').
 -}
data UnifiedVariable variable
    = ElemVar !(ElementVariable variable)
    | SetVar  !(SetVariable variable)
    deriving (Generic, Eq, Ord, Show, Functor, Foldable, Traversable)

instance NFData variable => NFData (UnifiedVariable variable)

instance SOP.Generic (UnifiedVariable variable)

instance SOP.HasDatatypeInfo (UnifiedVariable variable)

instance Debug variable => Debug (UnifiedVariable variable)

instance (Debug variable, Diff variable) => Diff (UnifiedVariable variable)

instance Hashable variable => Hashable (UnifiedVariable variable)

instance Unparse variable => Unparse (UnifiedVariable variable) where
    unparse = foldMapVariable unparse
    unparse2 = foldMapVariable unparse2

instance FreshVariable variable => FreshVariable (UnifiedVariable variable)
  where
    refreshVariable avoid = \case
        SetVar v -> SetVar <$> refreshVariable setVars v
        ElemVar v -> ElemVar <$> refreshVariable elemVars v
      where
        avoid' = Set.toList avoid
        setVars = Set.fromList [v | SetVar v <- avoid']
        elemVars = Set.fromList [v | ElemVar v <- avoid']

isElemVar :: UnifiedVariable variable -> Bool
isElemVar (ElemVar _) = True
isElemVar _ = False

{- | Extract an 'ElementVariable' from a 'UnifiedVariable'.

It is an error if the 'UnifiedVariable' is not the 'ElemVar' constructor.

Use @expectElemVar@ when maintaining the invariant outside the type system that
the 'UnifiedVariable' is an 'ElementVariable', but please include a comment at
the call site describing how the invariant is maintained.

 -}
expectElemVar
    :: HasCallStack
    => UnifiedVariable variable
    -> ElementVariable variable
expectElemVar (ElemVar elementVariable) = elementVariable
expectElemVar _ = error "Expected element variable"

isSetVar :: UnifiedVariable variable -> Bool
isSetVar (SetVar _) = True
isSetVar _ = False

{- | Extract an 'SetVariable' from a 'UnifiedVariable'.

It is an error if the 'UnifiedVariable' is not the 'SetVar' constructor.

Use @expectSetVar@ when maintaining the invariant outside the type system that
the 'UnifiedVariable' is an 'SetVariable', but please include a comment at
the call site describing how the invariant is maintained.

 -}
expectSetVar
    :: HasCallStack
    => UnifiedVariable variable
    -> SetVariable variable
expectSetVar (SetVar setVariable) = setVariable
expectSetVar _ = error "Expected set variable"

instance
    SortedVariable variable =>
    Synthetic Sort (Const (UnifiedVariable variable))
  where
    synthetic (Const var) = foldMapVariable sortedVariableSort var
    {-# INLINE synthetic #-}

extractElementVariable
    :: UnifiedVariable variable -> Maybe (ElementVariable variable)
extractElementVariable (ElemVar var) = Just var
extractElementVariable _ = Nothing

-- |Meant for extracting variable-related information from a 'UnifiedVariable'
foldMapVariable :: (variable -> a) -> UnifiedVariable variable -> a
foldMapVariable f (ElemVar v) = f (getElementVariable v)
foldMapVariable f (SetVar v) = f (getSetVariable v)

-- | The 'Sort' of a 'SetVariable' or an 'ElementVariable'.
unifiedVariableSort
    :: SortedVariable variable
    => UnifiedVariable variable
    -> Sort
unifiedVariableSort = foldMapVariable sortedVariableSort

refreshElementVariable
    :: FreshVariable (UnifiedVariable variable)
    => Set (UnifiedVariable variable)
    -> ElementVariable variable
    -> Maybe (ElementVariable variable)
refreshElementVariable avoiding =
    -- expectElemVar is safe because the FreshVariable instance of
    -- UnifiedVariable (above) conserves the ElemVar constructor.
    fmap expectElemVar . refreshVariable avoiding . ElemVar

refreshSetVariable
    :: FreshVariable (UnifiedVariable variable)
    => Set (UnifiedVariable variable)
    -> SetVariable variable
    -> Maybe (SetVariable variable)
refreshSetVariable avoiding =
    -- expectElemVar is safe because the FreshVariable instance of
    -- UnifiedVariable (above) conserves the SetVar constructor.
    fmap expectSetVar . refreshVariable avoiding . SetVar
