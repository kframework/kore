{-|
Copyright   : (c) Runtime Verification, 2019
License     : NCSA

-}

module Kore.Syntax.Iff
    ( Iff (..)
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

{-|'Iff' corresponds to the @\iff@ branches of the @object-pattern@ and
@meta-pattern@ syntactic categories from the Semantics of K,
Section 9.1.4 (Patterns).

'iffSort' is both the sort of the operands and the sort of the result.

-}
data Iff sort child = Iff
    { iffSort   :: !sort
    , iffFirst  :: child
    , iffSecond :: child
    }
    deriving (Eq, Ord, Show)
    deriving (Functor, Foldable, Traversable)
    deriving (GHC.Generic)
    deriving anyclass (Hashable, NFData)
    deriving anyclass (SOP.Generic, SOP.HasDatatypeInfo)
    deriving anyclass (Debug, Diff)

instance Unparse child => Unparse (Iff Sort child) where
    unparse Iff { iffSort, iffFirst, iffSecond } =
        "\\iff"
        <> parameters [iffSort]
        <> arguments [iffFirst, iffSecond]

    unparse2 Iff { iffFirst, iffSecond } =
        Pretty.parens (Pretty.fillSep
            [ "\\iff"
            , unparse2 iffFirst
            , unparse2 iffSecond
            ])

instance Ord variable => Synthetic (FreeVariables variable) (Iff sort) where
    synthetic = Foldable.fold
    {-# INLINE synthetic #-}

instance Synthetic Sort (Iff Sort) where
    synthetic Iff { iffSort, iffFirst, iffSecond } =
        iffSort
        & seq (matchSort iffSort iffFirst)
        . seq (matchSort iffSort iffSecond)
    {-# INLINE synthetic #-}
