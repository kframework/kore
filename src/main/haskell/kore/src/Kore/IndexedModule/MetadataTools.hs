{-|
Module      : Kore.IndexedModule.MetadataTools
Description : Datastructures and functionality for retrieving metadata
              information from patterns
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : traian.serbanuta@runtimeverification.com
Stability   : experimental
Portability : portable
-}
module Kore.IndexedModule.MetadataTools
    ( MetadataTools (..)
    , SortTools
    , extractMetadataTools
    , getResultSort
    ) where

import Kore.AST.Common
import Kore.AST.MetaOrObject
import Kore.ASTHelpers
import Kore.IndexedModule.IndexedModule
import Kore.IndexedModule.Resolvers

-- |'MetadataTools' defines a dictionary of functions which can be used to
-- access the metadata needed during the unification process.
data MetadataTools level attributes = MetadataTools
    { symAttributes :: SymbolOrAlias level -> attributes
    , sortAttributes :: Sort level -> attributes
    , sortTools  :: SortTools level
    , isSubsortOf :: Sort level -> Sort level -> Bool
    }

-- TODO: Rename this as `SortGetter` or something similar, `Tools` is
-- too general.
type SortTools level = SymbolOrAlias level -> ApplicationSorts level

-- |'extractMetadataTools' extracts a set of 'MetadataTools' from a
-- 'KoreIndexedModule'.  The metadata tools are functions yielding information
-- about application heads, such as its attributes or
-- its argument and result sorts.
--
extractMetadataTools
    :: MetaOrObject level
    => KoreIndexedModule atts
    -> MetadataTools level atts
extractMetadataTools m =
  MetadataTools
    { symAttributes = getHeadAttributes m
    , sortAttributes = getSortAttributes m
    , sortTools  = getHeadApplicationSorts m
    -- TODO: Implement.
    , isSubsortOf = const $ const $ False
    }

{- | Look up the result sort of a symbol or alias
 -}
getResultSort :: MetadataTools level attrs -> SymbolOrAlias level -> Sort level
getResultSort MetadataTools { sortTools } symbol =
    case sortTools symbol of
        ApplicationSorts { applicationSortsResult } -> applicationSortsResult

