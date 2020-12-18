{- |
Copyright   : (c) Runtime Verification, 2019
License     : NCSA
 -}
module Kore.Internal.InternalList
    ( InternalList (..)
    ) where

import Prelude.Kore

import Control.DeepSeq
    ( NFData
    )
import Data.Sequence
    ( Seq
    )
import qualified Generics.SOP as SOP
import qualified GHC.Generics as GHC

import Kore.Attribute.Pattern.ConstructorLike
import Kore.Attribute.Pattern.Defined
import Kore.Attribute.Pattern.FreeVariables
    ( FreeVariables
    )
import Kore.Attribute.Pattern.Function
import Kore.Attribute.Pattern.Functional
import Kore.Attribute.Pattern.Simplified
import Kore.Attribute.Synthetic
import Kore.Debug
import Kore.Internal.Symbol
import Kore.Sort
import Kore.Unparser

{- | Internal representation of the builtin @LIST.List@ domain.
 -}
data InternalList child =
    InternalList
        { internalListSort :: !Sort
        , internalListUnit :: !Symbol
        , internalListElement :: !Symbol
        , internalListConcat :: !Symbol
        , internalListChild :: !(Seq child)
        }
    deriving (Eq, Ord, Show)
    deriving (Foldable, Functor, Traversable)
    deriving (GHC.Generic)
    deriving anyclass (SOP.Generic, SOP.HasDatatypeInfo)
    deriving anyclass (Debug, Diff)

instance Hashable child => Hashable (InternalList child) where
    hashWithSalt salt internal =
        hashWithSalt salt (toList internalListChild)
      where
        InternalList { internalListChild } = internal

instance NFData child => NFData (InternalList child)

instance Unparse child => Unparse (InternalList child) where
    unparse internalList =
        unparseConcat'
            (unparse internalListUnit)
            (unparse internalListConcat)
            (element <$> toList internalListChild)
      where
        element x = unparse internalListElement <> arguments [x]
        InternalList { internalListChild } = internalList
        InternalList { internalListUnit } = internalList
        InternalList { internalListElement } = internalList
        InternalList { internalListConcat } = internalList

    unparse2 internalList =
        unparseConcat'
            (unparse internalListUnit)
            (unparse internalListConcat)
            (element <$> toList internalListChild)
      where
        element x = unparse2 internalListElement <> arguments2 [x]
        InternalList { internalListChild } = internalList
        InternalList { internalListUnit } = internalList
        InternalList { internalListElement } = internalList
        InternalList { internalListConcat } = internalList

instance Synthetic Sort InternalList where
    synthetic = internalListSort
    {-# INLINE synthetic #-}

instance Ord variable => Synthetic (FreeVariables variable) InternalList where
    synthetic = fold
    {-# INLINE synthetic #-}

instance Synthetic ConstructorLike InternalList where
    synthetic = const (ConstructorLike Nothing)
    {-# INLINE synthetic #-}

-- | A 'InternalInt' pattern is always 'Defined'.
instance Synthetic Defined InternalList where
    synthetic = fold
    {-# INLINE synthetic #-}

-- | An 'InternalList' pattern is always 'Function'.
instance Synthetic Function InternalList where
    synthetic = fold
    {-# INLINE synthetic #-}

-- | An 'InternalList' pattern is always 'Functional'.
instance Synthetic Functional InternalList where
    synthetic = fold
    {-# INLINE synthetic #-}

instance Synthetic Simplified InternalList where
    synthetic = notSimplified
    {-# INLINE synthetic #-}
