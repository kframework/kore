{-|
Copyright   : (c) Runtime Verification, 2019
License     : NCSA

-}

module Kore.Syntax.Bottom
    ( Bottom (..)
    ) where

import Prelude.Kore

import Control.DeepSeq
    ( NFData (..)
    )
import qualified Generics.SOP as SOP
import qualified GHC.Generics as GHC

import Kore.Attribute.Pattern.FreeVariables
import Kore.Attribute.Synthetic
import Kore.Debug
import Kore.Sort
import Kore.Unparser

{- | 'Bottom' corresponds to the @\bottom@ branches of the @pattern@ syntactic
category from the Semantics of K, Section 9.1.4 (Patterns).

'bottomSort' is the sort of the result.

 -}
newtype Bottom sort child = Bottom { bottomSort :: sort }
    deriving (Eq, Ord, Show)
    deriving (Functor, Foldable, Traversable)
    deriving (GHC.Generic)
    deriving anyclass (Hashable, NFData)
    deriving anyclass (SOP.Generic, SOP.HasDatatypeInfo)
    deriving anyclass (Debug, Diff)

instance Unparse (Bottom Sort child) where
    unparse Bottom { bottomSort } =
        "\\bottom" <> parameters [bottomSort] <> noArguments
    unparse2 _ = "\\bottom"

instance Synthetic (FreeVariables variable) (Bottom sort) where
    synthetic = const emptyFreeVariables
    {-# INLINE synthetic #-}

instance Synthetic Sort (Bottom Sort) where
    synthetic = bottomSort
    {-# INLINE synthetic #-}
