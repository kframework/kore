{-|
Copyright   : (c) Runtime Verification, 2019
License     : NCSA

-}

module Kore.Syntax.Floor
    ( Floor (..)
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
import qualified Pretty

{-|'Floor' corresponds to the @\floor@ branches of the @object-pattern@ and
@meta-pattern@ syntactic categories from the Semantics of K,
Section 9.1.4 (Patterns).

'floorOperandSort' is the sort of the operand.

'floorResultSort' is the sort of the result.

-}
data Floor sort child = Floor
    { floorOperandSort :: !sort
    , floorResultSort  :: !sort
    , floorChild       :: child
    }
    deriving (Eq, Ord, Show)
    deriving (Functor, Foldable, Traversable)
    deriving (GHC.Generic)
    deriving anyclass (Hashable, NFData)
    deriving anyclass (SOP.Generic, SOP.HasDatatypeInfo)
    deriving anyclass (Debug, Diff)

instance Unparse child => Unparse (Floor Sort child) where
    unparse Floor { floorOperandSort, floorResultSort, floorChild } =
        "\\floor"
        <> parameters [floorOperandSort, floorResultSort]
        <> arguments [floorChild]

    unparse2 Floor { floorChild } =
        Pretty.parens (Pretty.fillSep ["\\floor", unparse2 floorChild])

instance Synthetic (FreeVariables variable) (Floor sort) where
    synthetic = floorChild
    {-# INLINE synthetic #-}

instance Synthetic Sort (Floor Sort) where
    synthetic Floor { floorOperandSort, floorResultSort, floorChild } =
        floorResultSort
        & seq (matchSort floorOperandSort floorChild)
    {-# INLINE synthetic #-}
