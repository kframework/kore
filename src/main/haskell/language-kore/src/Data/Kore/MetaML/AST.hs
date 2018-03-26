{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE StandaloneDeriving    #-}
{-# LANGUAGE UndecidableInstances  #-}
{-|
Module      : Data.Kore.MetaML.AST
Description : Data Structures for representing a Meta-only version of the
              Kore language AST
Copyright   : (c) Runtime Verification, 2018
License     : UIUC/NCSA
Maintainer  : traian.serbanuta@runtimeverification.com
Stability   : experimental
Portability : portable

This module specializes the 'Data.Kore.AST.Common' datastructures for
representing definitions, modules, axioms, patterns that only use 'Meta'-level
constructs.

Please refer to Section 9 (The Kore Language) of the
<http://github.com/kframework/kore/blob/master/docs/semantics-of-k.pdf Semantics of K>.
-}
module Data.Kore.MetaML.AST where

import           Data.Fix

import           Data.Kore.AST.Common

{-|'MetaMLPattern' corresponds to "fixed point" representations
of the 'Pattern' class where the level is fixed to 'Meta'.

'var' is the type of variables.
-}
type MetaMLPattern var = Fix (Pattern Meta var)

newtype SentenceMetaPattern var = SentenceMetaPattern
    { getSentenceMetaPattern :: MetaMLPattern var }

deriving instance Eq (SentenceMetaPattern Variable)
deriving instance Show (SentenceMetaPattern Variable)

-- |'MetaAttributes' is the 'Meta'-only version of 'Attributes'
type MetaAttributes = Attributes SentenceMetaPattern Variable

type MetaSentenceAxiom =
    SentenceAxiom (SortVariable Meta) SentenceMetaPattern Variable
type MetaSentenceAlias = SentenceAlias Meta SentenceMetaPattern Variable
type MetaSentenceSymbol = SentenceSymbol Meta SentenceMetaPattern Variable
type MetaSentenceImport = SentenceImport SentenceMetaPattern Variable

type MetaSentence =
    Sentence Meta (SortVariable Meta) SentenceMetaPattern Variable

instance AsSentence MetaSentence MetaSentenceAlias where
    asSentence = SentenceAliasSentence

instance AsSentence MetaSentence MetaSentenceSymbol where
    asSentence = SentenceSymbolSentence

instance AsSentence MetaSentence MetaSentenceImport where
    asSentence = SentenceImportSentence

instance AsSentence MetaSentence MetaSentenceAxiom where
    asSentence = SentenceAxiomSentence

-- |'MetaModule' is the 'Meta'-only version of 'Module'.
type MetaModule =
    Module (Sentence Meta) (SortVariable Meta) SentenceMetaPattern Variable

-- |'MetaDefinition' is the 'Meta'-only version of 'Definition'.
type MetaDefinition =
    Definition (Sentence Meta) (SortVariable Meta) SentenceMetaPattern Variable

groundHead :: String -> SymbolOrAlias a
groundHead ctor = SymbolOrAlias
    { symbolOrAliasConstructor = Id ctor
    , symbolOrAliasParams = []
    }

groundSymbol :: String -> Symbol a
groundSymbol ctor = Symbol
    { symbolConstructor = Id ctor
    , symbolParams = []
    }

apply :: SymbolOrAlias a -> [p] -> Pattern a v p
apply patternHead patterns = ApplicationPattern Application
    { applicationSymbolOrAlias = patternHead
    , applicationChildren = patterns
    }

constant :: SymbolOrAlias a -> Pattern a v p
constant patternHead = apply patternHead []

nilSortListHead :: SymbolOrAlias Meta
nilSortListHead = groundHead "#nilSortList"

consSortListHead :: SymbolOrAlias Meta
consSortListHead = groundHead "#consSortList"

nilSortListMetaPattern :: MetaMLPattern v
nilSortListMetaPattern = Fix $ constant nilSortListHead

nilPatternListHead :: SymbolOrAlias Meta
nilPatternListHead = groundHead "#nilPatternList"

consPatternListHead :: SymbolOrAlias Meta
consPatternListHead = groundHead "#consPatternList"

nilPatternListMetaPattern :: MetaMLPattern v
nilPatternListMetaPattern = Fix $ constant nilPatternListHead

variableHead :: SymbolOrAlias Meta
variableHead = groundHead "#variable"

variableAsPatternHead :: SymbolOrAlias Meta
variableAsPatternHead = groundHead "#variableAsPattern"

metaMLPatternHead :: MLPatternType -> SymbolOrAlias Meta
metaMLPatternHead pt = groundHead ('#' : '\\' : patternString pt)

sortDeclaredHead :: Sort Meta -> SymbolOrAlias Meta
sortDeclaredHead param = SymbolOrAlias
    { symbolOrAliasConstructor = Id "#sortDeclared"
    , symbolOrAliasParams = [param]
    }

provableHead :: Sort Meta -> SymbolOrAlias Meta
provableHead param = SymbolOrAlias
    { symbolOrAliasConstructor = Id "#provable"
    , symbolOrAliasParams = [param]
    }

sortsDeclaredHead :: Sort Meta -> SymbolOrAlias Meta
sortsDeclaredHead param = SymbolOrAlias
    { symbolOrAliasConstructor = Id "#sortsDeclared"
    , symbolOrAliasParams = [param]
    }

symbolDeclaredHead :: Sort Meta -> SymbolOrAlias Meta
symbolDeclaredHead param = SymbolOrAlias
    { symbolOrAliasConstructor = Id "#symbolDeclared"
    , symbolOrAliasParams = [param]
    }

sortHead :: SymbolOrAlias Meta
sortHead = groundHead "#sort"

symbolHead :: SymbolOrAlias Meta
symbolHead = groundHead "#symbol"

applicationHead :: SymbolOrAlias Meta
applicationHead = groundHead "#application"

type CommonMetaPattern = MetaMLPattern Variable
type PatternMetaType = Pattern Meta Variable CommonMetaPattern

type MetaPatternStub = PatternStub Meta Variable CommonMetaPattern

{-|'dummyMetaSort' is used in error messages when we want to convert an
'UnsortedPatternStub' to a pattern that can be displayed.
-}
dummyMetaSort :: Sort Meta
dummyMetaSort = SortVariableSort (SortVariable (Id "#dummy"))
