{-# LANGUAGE Strict #-}
{- |
Copyright   : (c) Runtime Verification, 2019
License     : NCSA
-}
module Kore.Syntax.Top (
    Top (..),
) where

import qualified Generics.SOP as SOP
import qualified GHC.Generics as GHC
import Kore.Attribute.Pattern.FreeVariables
import Kore.Attribute.Synthetic
import Kore.Debug
import Kore.Sort
import Kore.Unparser
import Prelude.Kore

{- | 'Top' corresponds to the @\top{}()@ connective in Kore.

'topSort' is the sort of the result.
-}
newtype Top sort child = Top {topSort :: sort}
    deriving (Eq, Ord, Show)
    deriving (Functor, Foldable, Traversable)
    deriving (GHC.Generic)
    deriving anyclass (Hashable, NFData)
    deriving anyclass (SOP.Generic, SOP.HasDatatypeInfo)
    deriving anyclass (Debug, Diff)

instance Unparse (Top Sort child) where
    unparse Top{topSort} = "\\top" <> parameters [topSort] <> noArguments

    unparse2 _ = "\\top"

instance Unparse (Top () child) where
    unparse _ = "\\top" <> noArguments

    unparse2 _ = "\\top"

instance Synthetic (FreeVariables variable) (Top sort) where
    synthetic = const emptyFreeVariables
    {-# INLINE synthetic #-}

instance Synthetic Sort (Top Sort) where
    synthetic = topSort
    {-# INLINE synthetic #-}
