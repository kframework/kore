{- |
Copyright   : (c) Runtime Verification, 2019
License     : NCSA

 -}

module Kore.Builtin.List.List
    ( sort
    , asBuiltin
    , asPattern
    , asInternal
    , asTermLike
    , internalize
      -- * Symbols
    , lookupSymbolGet
    , isSymbolConcat
    , isSymbolElement
    , isSymbolUnit
      -- * Keys
    , concatKey
    , elementKey
    , unitKey
    , getKey
    , updateKey
    , inKey
    , sizeKey
    , makeKey
    , updateAllKey
    ) where

import Prelude.Kore

import Data.Reflection
    ( Given
    )
import qualified Data.Reflection as Reflection
import Data.Sequence
    ( Seq
    )
import qualified Data.Sequence as Seq
import Data.String
    ( IsString
    )
import Data.Text
    ( Text
    )

import qualified Kore.Attribute.Symbol as Attribute
import qualified Kore.Builtin.Symbols as Builtin
import qualified Kore.Error as Kore
import Kore.IndexedModule.IndexedModule
    ( VerifiedModule
    )
import Kore.IndexedModule.MetadataTools
    ( SmtMetadataTools
    )
import Kore.Internal.InternalList
import Kore.Internal.Pattern
    ( Pattern
    )
import qualified Kore.Internal.Pattern as Pattern
import Kore.Internal.TermLike

{- | Builtin variable name of the @List@ sort.
 -}
sort :: Text
sort = "LIST.List"

{- | Render an 'Domain.InternalList' as a 'TermLike' domain value pattern.

 -}
asTermLike
    :: InternalVariable variable
    => InternalList (TermLike variable)
    -> TermLike variable
asTermLike builtin
  | Seq.null list = unit
  | otherwise = foldr1 concat' (element <$> list)
  where
    InternalList { internalListChild = list } = builtin
    InternalList { internalListUnit = unitSymbol } = builtin
    InternalList { internalListElement = elementSymbol } = builtin
    InternalList { internalListConcat = concatSymbol } = builtin

    unit = mkApplySymbol unitSymbol []
    element elem' = mkApplySymbol elementSymbol [elem']
    concat' list1 list2 = mkApplySymbol concatSymbol [list1, list2]

{- | Render a 'Seq' as an expanded internal list pattern.
 -}
asInternal
    :: InternalVariable variable
    => SmtMetadataTools Attribute.Symbol
    -> Sort
    -> Seq (TermLike variable)
    -> TermLike variable
asInternal tools builtinListSort builtinListChild =
    mkInternalList (asBuiltin tools builtinListSort builtinListChild)

{- | Render a 'Seq' as a Builtin list pattern.
-}
asBuiltin
    :: SmtMetadataTools Attribute.Symbol
    -> Sort
    -> Seq (TermLike variable)
    -> InternalList (TermLike variable)
asBuiltin tools internalListSort internalListChild =
    InternalList
        { internalListSort
        , internalListUnit =
            Builtin.lookupSymbolUnit tools internalListSort
        , internalListElement =
            Builtin.lookupSymbolElement tools internalListSort
        , internalListConcat =
            Builtin.lookupSymbolConcat tools internalListSort
        , internalListChild
        }

{- | Render a 'Seq' as an extended domain value pattern.

See also: 'asPattern'

 -}
asPattern
    ::  ( InternalVariable variable
        , Given (SmtMetadataTools Attribute.Symbol)
        )
    => Sort
    -> Seq (TermLike variable)
    -> Pattern variable
asPattern resultSort =
    Pattern.fromTermLike . asInternal tools resultSort
  where
    tools :: SmtMetadataTools Attribute.Symbol
    tools = Reflection.given

internalize
    :: InternalVariable variable
    => SmtMetadataTools Attribute.Symbol
    -> TermLike variable
    -> TermLike variable
internalize tools termLike@(App_ symbol args)
  | isSymbolUnit    symbol , [ ] <- args = asInternal' (Seq.fromList args)
  | isSymbolElement symbol , [_] <- args = asInternal' (Seq.fromList args)
  | isSymbolConcat  symbol =
    case args of
        [InternalList_ list1, arg2              ]
          | (null . internalListChild) list1 -> arg2
        [arg1              , InternalList_ list2]
          | (null . internalListChild) list2 -> arg1
        [InternalList_ list1, InternalList_ list2] ->
            asInternal' (on (<>) internalListChild list1 list2)
        _ -> termLike
  where
    asInternal' = asInternal tools (termLikeSort termLike)
internalize _ termLike = termLike

{- | Find the symbol hooked to @LIST.get@ in an indexed module.
 -}
lookupSymbolGet
    :: Sort
    -> VerifiedModule Attribute.Symbol
    -> Either (Kore.Error e) Symbol
lookupSymbolGet = Builtin.lookupSymbol getKey

{- | Check if the given symbol is hooked to @LIST.concat@.
-}
isSymbolConcat :: Symbol -> Bool
isSymbolConcat = Builtin.isSymbol concatKey

{- | Check if the given symbol is hooked to @LIST.element@.
-}
isSymbolElement :: Symbol -> Bool
isSymbolElement = Builtin.isSymbol elementKey

{- | Check if the given symbol is hooked to @LIST.unit@.
-}
isSymbolUnit :: Symbol -> Bool
isSymbolUnit = Builtin.isSymbol unitKey

concatKey :: IsString s => s
concatKey = "LIST.concat"

elementKey :: IsString s => s
elementKey = "LIST.element"

unitKey :: IsString s => s
unitKey = "LIST.unit"

getKey :: IsString s => s
getKey = "LIST.get"

updateKey :: IsString s => s
updateKey = "LIST.update"

inKey :: IsString s => s
inKey = "LIST.in"

sizeKey :: IsString s => s
sizeKey = "LIST.size"

makeKey :: IsString s => s
makeKey = "LIST.make"

updateAllKey :: IsString s => s
updateAllKey = "LIST.updateAll"
