{-|
Copyright   : (c) Runtime Verification, 2019
License     : NCSA

-}

module Kore.Syntax.Or
    ( Or (..)
    ) where

import Prelude.Kore

import Control.DeepSeq
    ( NFData (..)
    )
import qualified Data.Foldable as Foldable
import qualified Generics.SOP as SOP
import qualified GHC.Generics as GHC

import Kore.Attribute.Pattern.FreeVariables
import Kore.Attribute.Synthetic
import Kore.Debug
import Kore.Sort
import Kore.Unparser
import qualified Pretty

{-|'Or' corresponds to the @\or@ branches of the @object-pattern@ and
@meta-pattern@ syntactic categories from the Semantics of K,
Section 9.1.4 (Patterns).

'orSort' is both the sort of the operands and the sort of the result.

-}
data Or sort child = Or
    { orSort   :: !sort
    , orFirst  :: child
    , orSecond :: child
    }
    deriving (Eq, Ord, Show)
    deriving (Functor, Foldable, Traversable)
    deriving (GHC.Generic)
    deriving anyclass (Hashable, NFData)
    deriving anyclass (SOP.Generic, SOP.HasDatatypeInfo)
    deriving anyclass (Debug, Diff)

instance Unparse child => Unparse (Or Sort child) where
    unparse Or { orSort, orFirst, orSecond } =
        "\\or"
        <> parameters [orSort]
        <> arguments [orFirst, orSecond]

    unparse2 Or { orFirst, orSecond } =
        Pretty.parens (Pretty.fillSep
            [ "\\or"
            , unparse2 orFirst
            , unparse2 orSecond
            ])

instance Ord variable => Synthetic (FreeVariables variable) (Or sort) where
    synthetic = Foldable.fold
    {-# INLINE synthetic #-}

instance Synthetic Sort (Or Sort) where
    synthetic Or { orSort, orFirst, orSecond } =
        orSort
        & seq (matchSort orSort orFirst)
        . seq (matchSort orSort orSecond)
    {-# INLINE synthetic #-}
