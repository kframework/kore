{-|
Copyright   : (c) Runtime Verification, 2019
License     : NCSA
-}
module Kore.AST.ApplicativeKore
    ( completeDefinition ) where

import           Kore.AST.Valid
import           Kore.Step.TermLike as TermLike
import           Kore.Syntax.Definition
import qualified Kore.Verified as Verified

completeDefinition
    :: Definition Verified.Sentence
    -> Definition Verified.Sentence
completeDefinition Definition { definitionAttributes, definitionModules } =
    Definition
    { definitionAttributes
    , definitionModules = map completeModule definitionModules
    }

completeModule :: Module Verified.Sentence -> Module Verified.Sentence
completeModule Module { moduleName, moduleSentences, moduleAttributes } =
    Module
    { moduleName
    , moduleSentences = concatMap completeSentence moduleSentences
    , moduleAttributes
    }

completeSentence :: Verified.Sentence -> [Verified.Sentence]
completeSentence (SentenceAxiomSentence sentenceAxiom) =
    [ SentenceAxiomSentence sentenceAxiom
        { sentenceAxiomPattern = quantifiedAxiomPattern }
    ]
 where
   quantifiedAxiomPattern =
       quantifyFreeVariables (sentenceAxiomPattern sentenceAxiom)
completeSentence s = [s]

quantifyFreeVariables :: TermLike Variable -> TermLike Variable
quantifyFreeVariables termLike =
    foldr mkForall termLike
    $ TermLike.freeVariables termLike
