{-|
Module      : Kore.Domain.Builtin
Description : Internal representation of internal domains
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : thomas.tuegel@runtimeverification.com
-}

{-# LANGUAGE TemplateHaskell #-}

module Kore.Domain.Builtin
    ( Builtin (..)
    , builtinSort
    , InternalMap (..)
    , lensBuiltinMapSort
    , lensBuiltinMapUnit
    , lensBuiltinMapElement
    , lensBuiltinMapConcat
    , lensBuiltinMapChild
    , InternalList (..)
    , lensBuiltinListSort
    , lensBuiltinListUnit
    , lensBuiltinListElement
    , lensBuiltinListConcat
    , lensBuiltinListChild
    , InternalSet (..)
    , NormalizedSet (..)
    , emptyNormalizedSet
    , lensBuiltinSetSort
    , lensBuiltinSetUnit
    , lensBuiltinSetElement
    , lensBuiltinSetConcat
    , lensBuiltinSetChild
    , InternalInt (..)
    , lensBuiltinIntSort
    , lensBuiltinIntValue
    , InternalBool (..)
    , lensBuiltinBoolSort
    , lensBuiltinBoolValue
    , InternalString (..)
    , lensInternalStringSort
    , lensInternalStringValue
    , Domain (..)
    ) where

import           Control.DeepSeq
                 ( NFData (..) )
import qualified Data.Foldable as Foldable
import           Data.Hashable
import           Data.Map
                 ( Map )
import qualified Data.Map as Map
import           Data.Sequence
                 ( Seq )
import           Data.Set
                 ( Set )
import qualified Data.Set as Set
import           Data.Text
                 ( Text )
import qualified Data.Text.Prettyprint.Doc as Pretty
import qualified Generics.SOP as SOP
import qualified GHC.Generics as GHC

import Control.Lens.TH.Rules
       ( makeLenses )
import Kore.Attribute.Synthetic
import Kore.Debug
import Kore.Domain.Class
import Kore.Internal.Symbol
import Kore.Syntax
import Kore.Unparser

-- * Helpers

{- | Unparse a builtin collection type, given its symbols and children.

The children are already unparsed.

 -}
unparseCollection
    :: Symbol  -- ^ unit symbol
    -> Symbol  -- ^ element symbol
    -> Symbol  -- ^ concat symbol
    -> [Pretty.Doc ann]      -- ^ children
    -> Pretty.Doc ann
unparseCollection unitSymbol elementSymbol concatSymbol =
    \case
        [] -> applyUnit
        xs -> foldr1 applyConcat (applyElement <$> xs)
  where
    applyUnit = unparse unitSymbol <> noArguments
    applyElement elem' = unparse elementSymbol <> elem'
    applyConcat set1 set2 = unparse concatSymbol <> arguments' [set1, set2]

-- * Builtin Map

{- | Internal representation of the builtin @MAP.Map@ domain.
 -}
data InternalMap key child =
    InternalMap
        { builtinMapSort :: !Sort
        , builtinMapUnit :: !Symbol
        , builtinMapElement :: !Symbol
        , builtinMapConcat :: !Symbol
        , builtinMapChild :: !(Map key child)
        }
    deriving (Eq, Foldable, Functor, GHC.Generic, Ord, Show, Traversable)

instance
    (Hashable key, Hashable child) =>
    Hashable (InternalMap key child)
  where
    hashWithSalt salt builtin =
        hashWithSalt salt (Map.toAscList builtinMapChild)
      where
        InternalMap { builtinMapChild } = builtin

instance (NFData key, NFData child) => NFData (InternalMap key child)

instance SOP.Generic (InternalMap key child)

instance SOP.HasDatatypeInfo (InternalMap key child)

instance (Debug key, Debug child) => Debug (InternalMap key child)

instance (Unparse key, Unparse child) => Unparse (InternalMap key child) where
    unparse builtinMap =
        unparseCollection
            builtinMapUnit
            builtinMapElement
            builtinMapConcat
            (unparseElementArguments <$> Map.toAscList builtinMapChild)
      where
        InternalMap { builtinMapChild } = builtinMap
        InternalMap { builtinMapUnit } = builtinMap
        InternalMap { builtinMapElement } = builtinMap
        InternalMap { builtinMapConcat } = builtinMap
        unparseElementArguments (key, value) =
            arguments' [unparse key, unparse value]

    unparse2 builtinMap =
        unparseCollection
            builtinMapUnit
            builtinMapElement
            builtinMapConcat
            (unparseElementArguments <$> Map.toAscList builtinMapChild)
      where
        InternalMap { builtinMapChild } = builtinMap
        InternalMap { builtinMapUnit } = builtinMap
        InternalMap { builtinMapElement } = builtinMap
        InternalMap { builtinMapConcat } = builtinMap
        unparseElementArguments (key, value) =
            arguments' [unparse2 key, unparse2 value]

-- * Builtin List

{- | Internal representation of the builtin @LIST.List@ domain.
 -}
data InternalList child =
    InternalList
        { builtinListSort :: !Sort
        , builtinListUnit :: !Symbol
        , builtinListElement :: !Symbol
        , builtinListConcat :: !Symbol
        , builtinListChild :: !(Seq child)
        }
    deriving (Eq, Foldable, Functor, GHC.Generic, Ord, Show, Traversable)

instance SOP.Generic (InternalList child)

instance SOP.HasDatatypeInfo (InternalList child)

instance Debug child => Debug (InternalList child)

instance Hashable child => Hashable (InternalList child) where
    hashWithSalt salt builtin =
        hashWithSalt salt (Foldable.toList builtinListChild)
      where
        InternalList { builtinListChild } = builtin

instance NFData child => NFData (InternalList child)

instance Unparse child => Unparse (InternalList child) where
    unparse builtinList =
        unparseCollection
            builtinListUnit
            builtinListElement
            builtinListConcat
            (argument' . unparse <$> Foldable.toList builtinListChild)
      where
        InternalList { builtinListChild } = builtinList
        InternalList { builtinListUnit } = builtinList
        InternalList { builtinListElement } = builtinList
        InternalList { builtinListConcat } = builtinList

    unparse2 builtinList =
        unparseCollection
            builtinListUnit
            builtinListElement
            builtinListConcat
            (argument' . unparse2 <$> Foldable.toList builtinListChild)
      where
        InternalList { builtinListChild } = builtinList
        InternalList { builtinListUnit } = builtinList
        InternalList { builtinListElement } = builtinList
        InternalList { builtinListConcat } = builtinList

-- * Builtin Set

{- | Optimized set representation, with elements separated from
other set terms, and with concrete elements separated from non-concrete ones.
-}
data NormalizedSet key child = NormalizedSet
    { elementsWithVariables :: [child]
    -- ^ Non-concrete elements of the set. These would be of sort @Int@s for a
    -- set with @Int@ elements.
    , concreteElements :: Set key
    -- ^ Concrete elements of the set. These would be of sort @Int@s for a set
    -- with @Int@ elements.
    , sets :: [child]
    -- ^ Unoptimized (non-element) parts of the set.
    }
    deriving (Eq, Foldable, Functor, Traversable, GHC.Generic, Ord, Show)

instance (Hashable key, Hashable child) => Hashable (NormalizedSet key child)
  where
    hashWithSalt salt normalized@(NormalizedSet _ _ _) =
        salt
            `hashWithSalt` elementsWithVariables
            `hashWithSalt` Set.toList concreteElements
            `hashWithSalt` sets
      where
        NormalizedSet { elementsWithVariables } = normalized
        NormalizedSet { concreteElements } = normalized
        NormalizedSet { sets } = normalized

instance (NFData key, NFData child) => NFData (NormalizedSet key child)

instance SOP.Generic (NormalizedSet key child)

instance SOP.HasDatatypeInfo (NormalizedSet key child)

instance (Debug key, Debug child) => Debug (NormalizedSet key child)

emptyNormalizedSet :: NormalizedSet key child
emptyNormalizedSet = NormalizedSet
    { elementsWithVariables = []
    , concreteElements = Set.empty
    , sets = []
    }

{- | Internal representation of the builtin @SET.Set@ domain.
 -}
data InternalSet key child =
    InternalSet
        { builtinSetSort :: !Sort
        , builtinSetUnit :: !Symbol
        , builtinSetElement :: !Symbol
        , builtinSetConcat :: !Symbol
        , builtinSetChild :: !(NormalizedSet key child)
        }
    deriving (Eq, Foldable, Functor, Traversable, GHC.Generic, Ord, Show)

instance (Hashable key, Hashable child) => Hashable (InternalSet key child)
  where
    hashWithSalt salt builtin =
        hashWithSalt salt builtinSetChild
      where
        InternalSet { builtinSetChild } = builtin

instance (NFData key, NFData child) => NFData (InternalSet key child)

instance SOP.Generic (InternalSet key child)

instance SOP.HasDatatypeInfo (InternalSet key child)

instance (Debug key, Debug child) => Debug (InternalSet key child)

instance (Unparse key, Unparse child) => Unparse (InternalSet key child)
  where
    unparse = unparseInternalSet unparse unparse
    unparse2 = unparseInternalSet unparse2 unparse2

unparseInternalSet
    :: (key -> Pretty.Doc ann)
    -> (child -> Pretty.Doc ann)
    -> InternalSet key child
    -> Pretty.Doc ann
unparseInternalSet keyUnparser childUnparser builtinSet =
    unparseCollection
        builtinSetUnit
        builtinSetElement
        builtinSetConcat
        unparsedChildren
    where
    InternalSet { builtinSetChild } = builtinSet
    InternalSet { builtinSetUnit } = builtinSet
    InternalSet { builtinSetElement } = builtinSet
    InternalSet { builtinSetConcat } = builtinSet

    NormalizedSet {elementsWithVariables} = builtinSetChild
    NormalizedSet {concreteElements} = builtinSetChild
    NormalizedSet {sets} = builtinSetChild

    -- case statement needed only for getting compiler notifications when
    -- the NormalizedSet field count changes
    unparsedChildren = case builtinSetChild of
        NormalizedSet _ _ _ ->
            (argument' . childUnparser <$> elementsWithVariables)
            ++ (argument' . keyUnparser <$> Set.toList concreteElements)
            ++ (argument' . childUnparser <$> sets)

-- * Builtin Int

{- | Internal representation of the builtin @INT.Int@ domain.
 -}
data InternalInt =
    InternalInt
        { builtinIntSort :: !Sort
        , builtinIntValue :: !Integer
        }
    deriving (Eq, GHC.Generic, Ord, Show)

instance Hashable InternalInt

instance NFData InternalInt

instance SOP.Generic InternalInt

instance SOP.HasDatatypeInfo InternalInt

instance Debug InternalInt

instance Unparse InternalInt where
    unparse InternalInt { builtinIntSort, builtinIntValue } =
        "\\dv"
        <> parameters [builtinIntSort]
        <> arguments' [Pretty.dquotes $ Pretty.pretty builtinIntValue]

    unparse2 InternalInt { builtinIntSort, builtinIntValue } =
        "\\dv2"
        <> parameters2 [builtinIntSort]
        <> arguments' [Pretty.dquotes $ Pretty.pretty builtinIntValue]

-- * Builtin Bool

{- | Internal representation of the builtin @BOOL.Bool@ domain.
 -}
data InternalBool =
    InternalBool
        { builtinBoolSort :: !Sort
        , builtinBoolValue :: !Bool
        }
    deriving (Eq, GHC.Generic, Ord, Show)

instance Hashable InternalBool

instance NFData InternalBool

instance SOP.Generic InternalBool

instance SOP.HasDatatypeInfo InternalBool

instance Debug InternalBool

instance Unparse InternalBool where
    unparse InternalBool { builtinBoolSort, builtinBoolValue } =
        "\\dv"
        <> parameters [builtinBoolSort]
        <> arguments' [Pretty.dquotes value]
      where
        value
          | builtinBoolValue = "true"
          | otherwise        = "false"

    unparse2 InternalBool { builtinBoolSort, builtinBoolValue } =
        "\\dv2"
        <> parameters2 [builtinBoolSort]
        <> arguments' [Pretty.dquotes value]
      where
        value
          | builtinBoolValue = "true"
          | otherwise        = "false"

-- * Builtin String

{- | Internal representation of the builtin @STRING.String@ domain.
 -}
data InternalString =
    InternalString
        { internalStringSort :: !Sort
        , internalStringValue :: !Text
        }
    deriving (Eq, GHC.Generic, Ord, Show)

instance Hashable InternalString

instance NFData InternalString

instance SOP.Generic InternalString

instance SOP.HasDatatypeInfo InternalString

instance Debug InternalString

instance Unparse InternalString where
    unparse InternalString { internalStringSort, internalStringValue } =
        "\\dv"
        <> parameters [internalStringSort]
        <> arguments [StringLiteral internalStringValue]

    unparse2 InternalString { internalStringSort, internalStringValue } =
        "\\dv2"
        <> parameters2 [internalStringSort]
        <> arguments2 [StringLiteral internalStringValue]

-- * Builtin domain representations

data Builtin key child
    = BuiltinMap !(InternalMap key child)
    | BuiltinList !(InternalList child)
    | BuiltinSet !(InternalSet key child)
    | BuiltinInt !InternalInt
    | BuiltinBool !InternalBool
    | BuiltinString !InternalString
    deriving (Eq, Foldable, Functor, GHC.Generic, Ord, Show, Traversable)

instance SOP.Generic (Builtin key child)

instance SOP.HasDatatypeInfo (Builtin key child)

instance (Debug key, Debug child) => Debug (Builtin key child)

instance (Hashable key, Hashable child) => Hashable (Builtin key child)

instance (NFData key, NFData child) => NFData (Builtin key child)

instance (Unparse key, Unparse child) => Unparse (Builtin key child) where
    unparse evaluated =
        Pretty.sep ["/* builtin: */", unparseGeneric evaluated]
    unparse2 evaluated =
        Pretty.sep ["/* builtin: */", unparse2Generic evaluated]

builtinSort :: Builtin key child -> Sort
builtinSort builtin =
    case builtin of
        BuiltinInt InternalInt { builtinIntSort } -> builtinIntSort
        BuiltinBool InternalBool { builtinBoolSort } -> builtinBoolSort
        BuiltinString InternalString { internalStringSort } -> internalStringSort
        BuiltinMap InternalMap { builtinMapSort } -> builtinMapSort
        BuiltinList InternalList { builtinListSort } -> builtinListSort
        BuiltinSet InternalSet { builtinSetSort } -> builtinSetSort

instance Synthetic (Builtin key) Sort where
    synthetic = builtinSort
    {-# INLINE synthetic #-}

makeLenses ''InternalMap
makeLenses ''InternalList
makeLenses ''InternalSet
makeLenses ''InternalInt
makeLenses ''InternalBool
makeLenses ''InternalString

instance Domain (Builtin key) where
    lensDomainValue mapDomainValue builtin =
        getBuiltin <$> mapDomainValue original
      where
        original =
            DomainValue
                { domainValueChild = builtin
                , domainValueSort = builtinSort builtin
                }
        getBuiltin
            :: forall child
            .  DomainValue Sort (Builtin key child)
            -> Builtin key child
        getBuiltin DomainValue { domainValueSort, domainValueChild } =
            case domainValueChild of
                BuiltinInt internal ->
                    BuiltinInt internal { builtinIntSort = domainValueSort }
                BuiltinBool internal ->
                    BuiltinBool internal { builtinBoolSort = domainValueSort }
                BuiltinString internal ->
                    BuiltinString internal
                        { internalStringSort = domainValueSort }
                BuiltinMap internal ->
                    BuiltinMap internal { builtinMapSort = domainValueSort }
                BuiltinList internal ->
                    BuiltinList internal { builtinListSort = domainValueSort }
                BuiltinSet internal ->
                    BuiltinSet internal { builtinSetSort = domainValueSort }
