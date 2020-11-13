{- |
Copyright   : (c) Runtime Verification, 2019
License     : NCSA
 -}
module Kore.Verified
    ( Pattern
    , Alias
    , Sentence
    , SentenceAlias
    , SentenceAxiom
    , SentenceClaim
    , SentenceHook
    , SentenceImport
    , SentenceSort
    , SentenceSymbol
    ) where

import Prelude.Kore ()

import qualified Kore.Internal.Alias as Internal
    ( Alias
    )
import Kore.Internal.TermLike
    ( TermLike
    , VariableName
    )
import qualified Kore.Syntax.Sentence as Syntax

type Pattern = TermLike VariableName

type Alias = Internal.Alias Pattern

type Sentence = Syntax.Sentence Pattern

type SentenceAlias = Syntax.SentenceAlias Pattern

type SentenceAxiom = Syntax.SentenceAxiom Pattern

type SentenceClaim = Syntax.SentenceClaim Pattern

type SentenceHook = Syntax.SentenceHook

type SentenceImport = Syntax.SentenceImport

type SentenceSort = Syntax.SentenceSort

type SentenceSymbol = Syntax.SentenceSymbol
