{-|
Module      : Kore.AST.PureToKore
Description : Functionality for viewing "Pure"-only as unified Kore constructs.
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : traian.serbanuta@runtimeverification.com
Stability   : experimental
Portability : portable

The name of the functions defined below are self-explanatory. They link @Pure@
structures from "Kore.AST.PureML" to their @Kore@ counterparts in
"Kore.AST.Kore"

-}
module Kore.AST.PureToKore
    ( patternPureToKore
    , sentencePureToKore
    , axiomSentencePureToKore
    , modulePureToKore
    , definitionPureToKore
    , patternKoreToPure
    ) where

import Data.Functor.Foldable

import           Kore.AST.Common
import           Kore.AST.Kore
import           Kore.AST.MetaOrObject
import           Kore.AST.Sentence
import qualified Kore.Domain.Builtin as Domain
import           Kore.Error

patternPureToKore
    :: MetaOrObject level
    => CommonPurePattern level Domain.Builtin
    -> CommonKorePattern
patternPureToKore = cata asKorePattern

-- |Given a level, this function attempts to extract a pure patten
-- of this level from a KorePattern.
-- Note that this function does not lift the term, but rather fails with
-- 'error' any part of the pattern if of a different level.
-- For lifting functions see "Kore.MetaML.Lift".
patternKoreToPure
    :: MetaOrObject level
    => level
    -> CommonKorePattern
    -> Either (Error a) (CommonPurePattern level Domain.Builtin)
patternKoreToPure level = patternBottomUpVisitor (extractPurePattern level)

extractPurePattern
    :: (MetaOrObject level, MetaOrObject level1, Traversable domain)
    => level
    -> Pattern level1 domain Variable
        (Either (Error a) (CommonPurePattern level domain))
    -> Either (Error a) (CommonPurePattern level domain)
extractPurePattern level p =
    case (getMetaOrObjectPatternType p, isMetaOrObject (toProxy level)) of
        (IsMeta, IsMeta) -> fmap Fix (sequence p)
        (IsObject, IsObject) -> fmap Fix (sequence p)
        _ -> koreFail ("Unexpected non-" ++ show level ++ " pattern")

-- FIXME : all of this attribute record syntax stuff
-- Should be temporary measure
sentencePureToKore
    :: MetaOrObject level
    => PureSentence level Domain.Builtin
    -> KoreSentence
sentencePureToKore (SentenceAliasSentence sa) =
    asSentence $ aliasSentencePureToKore sa
sentencePureToKore (SentenceSymbolSentence (SentenceSymbol a b c d)) =
    constructUnifiedSentence SentenceSymbolSentence $ SentenceSymbol a b c d
sentencePureToKore (SentenceImportSentence (SentenceImport a b)) =
    constructUnifiedSentence SentenceImportSentence $ SentenceImport a b
sentencePureToKore (SentenceAxiomSentence msx) =
    asSentence (axiomSentencePureToKore msx)
sentencePureToKore (SentenceClaimSentence msx) =
    asSentence (axiomSentencePureToKore msx)
sentencePureToKore (SentenceSortSentence mss) =
  constructUnifiedSentence SentenceSortSentence mss
    { sentenceSortName = sentenceSortName mss
    , sentenceSortParameters = sentenceSortParameters mss
    }
sentencePureToKore (SentenceHookSentence (SentenceHookedSort mss)) =
  constructUnifiedSentence (SentenceHookSentence . SentenceHookedSort) mss
    { sentenceSortName = sentenceSortName mss
    , sentenceSortParameters = sentenceSortParameters mss
    }
sentencePureToKore (SentenceHookSentence (SentenceHookedSymbol (SentenceSymbol a b c d))) =
    constructUnifiedSentence (SentenceHookSentence . SentenceHookedSymbol) $ SentenceSymbol a b c d

aliasSentencePureToKore
    :: MetaOrObject level
    => PureSentenceAlias level Domain.Builtin
    -> KoreSentenceAlias level
aliasSentencePureToKore msx = msx
    { sentenceAliasLeftPattern =
        patternPureToKore <$> sentenceAliasLeftPattern msx
    , sentenceAliasRightPattern =
        patternPureToKore <$> sentenceAliasRightPattern msx
    }

axiomSentencePureToKore
    :: MetaOrObject level
    => PureSentenceAxiom level Domain.Builtin
    -> KoreSentenceAxiom
axiomSentencePureToKore msx = msx
    { sentenceAxiomPattern =
        patternPureToKore (sentenceAxiomPattern msx)
    , sentenceAxiomParameters =
        map asUnified (sentenceAxiomParameters msx)
    }

modulePureToKore
    :: MetaOrObject level
    => PureModule level Domain.Builtin
    -> KoreModule
modulePureToKore mm = Module
    { moduleName = moduleName mm
    , moduleSentences = map sentencePureToKore (moduleSentences mm)
    , moduleAttributes =  moduleAttributes mm
    }

definitionPureToKore
    :: MetaOrObject level
    => PureDefinition level Domain.Builtin
    -> KoreDefinition
definitionPureToKore dm = Definition
    { definitionAttributes = definitionAttributes dm
    , definitionModules = map modulePureToKore (definitionModules dm)
    }
