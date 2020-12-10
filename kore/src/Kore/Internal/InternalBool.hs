{- |
Copyright   : (c) Runtime Verification, 2019
License     : NCSA
 -}
module Kore.Internal.InternalBool
    ( InternalBool (..)
    ) where

import Prelude.Kore

import Control.DeepSeq
    ( NFData
    )
import Data.Functor.Const
import qualified Generics.SOP as SOP
import qualified GHC.Generics as GHC

import Kore.Attribute.Pattern.ConstructorLike
import Kore.Attribute.Pattern.Defined
import Kore.Attribute.Pattern.FreeVariables
import Kore.Attribute.Pattern.Function
import Kore.Attribute.Pattern.Functional
import Kore.Attribute.Pattern.Simplified
import Kore.Attribute.Synthetic
import Kore.Debug
import Kore.Sort
import Kore.Unparser
import qualified Pretty

{- | Internal representation of the builtin @BOOL.Bool@ domain.
 -}
data InternalBool =
    InternalBool
        { internalBoolSort :: !Sort
        , internalBoolValue :: !Bool
        }
    deriving (Eq, Ord, Show)
    deriving (GHC.Generic)
    deriving anyclass (Hashable, NFData)
    deriving anyclass (SOP.Generic, SOP.HasDatatypeInfo)
    deriving anyclass (Debug, Diff)

instance Unparse InternalBool where
    unparse InternalBool { internalBoolSort, internalBoolValue } =
        "\\dv"
        <> parameters [internalBoolSort]
        <> Pretty.parens (Pretty.dquotes value)
      where
        value
          | internalBoolValue = "true"
          | otherwise        = "false"

    unparse2 InternalBool { internalBoolSort, internalBoolValue } =
        "\\dv2"
        <> parameters2 [internalBoolSort]
        <> arguments' [Pretty.dquotes value]
      where
        value
          | internalBoolValue = "true"
          | otherwise        = "false"

instance Synthetic Sort (Const InternalBool) where
    synthetic (Const InternalBool { internalBoolSort }) = internalBoolSort
    {-# INLINE synthetic #-}

instance Synthetic (FreeVariables variable) (Const InternalBool) where
    synthetic _ = emptyFreeVariables
    {-# INLINE synthetic #-}

instance Synthetic ConstructorLike (Const InternalBool) where
    synthetic _ = ConstructorLike . Just $ ConstructorLikeHead
    {-# INLINE synthetic #-}

-- | A 'InternalInt' pattern is always 'Defined'.
instance Synthetic Defined (Const InternalBool) where
    synthetic = alwaysDefined
    {-# INLINE synthetic #-}

-- | An 'InternalBool' pattern is always 'Function'.
instance Synthetic Function (Const InternalBool) where
    synthetic = const (Function True)
    {-# INLINE synthetic #-}

-- | An 'InternalBool' pattern is always 'Functional'.
instance Synthetic Functional (Const InternalBool) where
    synthetic = const (Functional True)
    {-# INLINE synthetic #-}

instance Synthetic Simplified (Const InternalBool) where
    synthetic = alwaysSimplified
    {-# INLINE synthetic #-}