{-|
Module      : Kore.ASTVerifier.SentenceVerifier
Description : Tools for verifying the wellformedness of a Kore 'Sentence'.
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : virgil.serbanuta@runtimeverification.com
Stability   : experimental
Portability : POSIX
-}
module Kore.ASTVerifier.SentenceVerifier
    ( verifyUniqueNames
    , verifySentences
    , verifySentencesNEW
    , noConstructorWithDomainValuesMessage
    ) where

import Debug.Trace

import           Control.Error.Util
                 ( hush, note )
import           Control.Monad
                 ( foldM )
import           Data.Function
import           Data.Map
                 ( Map )
import qualified Data.Map as Map
import           Data.Maybe
                 ( isJust )
import qualified Data.Set as Set
import           Data.Text
                 ( Text )

import           Kore.AST.Error
import           Kore.ASTVerifier.AttributesVerifier
import           Kore.ASTVerifier.Error
import           Kore.ASTVerifier.PatternVerifier as PatternVerifier
import           Kore.ASTVerifier.SortVerifier
import qualified Kore.Attribute.Constructor as Attribute
import qualified Kore.Attribute.Hook as Attribute
import qualified Kore.Attribute.Parser as Attribute.Parser
import qualified Kore.Attribute.Sort as Attribute.Sort
import qualified Kore.Attribute.Sort as Attribute
                 ( Sort )
import qualified Kore.Attribute.Sort.HasDomainValues as Attribute.HasDomainValues
import qualified Kore.Attribute.Symbol as Attribute
import qualified Kore.Builtin as Builtin
import           Kore.Error
import           Kore.IndexedModule.Error
                 ( noSortText )
import           Kore.IndexedModule.IndexedModule as IndexedModule
import           Kore.IndexedModule.Resolvers
import           Kore.Sort
import           Kore.Syntax.Definition
import qualified Kore.Verified as Verified

{-|'verifyUniqueNames' verifies that names defined in a list of sentences are
unique both within the list and outside, using the provided name set.
-}
verifyUniqueNames
    :: [Sentence pat]
    -> Map.Map Text AstLocation
    -- ^ Names that are already defined.
    -> Either (Error VerifyError) (Map.Map Text AstLocation)
    -- ^ On success returns the names that were previously defined together with
    -- the names defined in the given 'Module'.
verifyUniqueNames sentences existingNames =
    foldM verifyUniqueId existingNames definedNames
  where
    definedNames =
        concatMap definedNamesForSentence sentences

data UnparameterizedId = UnparameterizedId
    { unparameterizedIdName     :: Text
    , unparameterizedIdLocation :: AstLocation
    }
    deriving (Show)

toUnparameterizedId :: Id -> UnparameterizedId
toUnparameterizedId Id {getId = name, idLocation = location} =
    UnparameterizedId
        { unparameterizedIdName = name
        , unparameterizedIdLocation = location
        }

verifyUniqueId
    :: Map.Map Text AstLocation
    -> UnparameterizedId
    -> Either (Error VerifyError) (Map.Map Text AstLocation)
verifyUniqueId existing (UnparameterizedId name location) =
    case Map.lookup name existing of
        Just location' ->
            koreFailWithLocations [location, location']
                ("Duplicated name: '" <> name <> "'.")
        _ -> Right (Map.insert name location existing)

definedNamesForSentence :: Sentence pat -> [UnparameterizedId]
definedNamesForSentence (SentenceAliasSentence sentenceAlias) =
    [ toUnparameterizedId (getSentenceSymbolOrAliasConstructor sentenceAlias) ]
definedNamesForSentence (SentenceSymbolSentence sentenceSymbol) =
    [ toUnparameterizedId (getSentenceSymbolOrAliasConstructor sentenceSymbol) ]
definedNamesForSentence (SentenceImportSentence _) = []
definedNamesForSentence (SentenceAxiomSentence _)  = []
definedNamesForSentence (SentenceClaimSentence _)  = []
definedNamesForSentence (SentenceSortSentence sentenceSort) =
    [ toUnparameterizedId (sentenceSortName sentenceSort) ]
definedNamesForSentence (SentenceHookSentence (SentenceHookedSort sentence)) =
    definedNamesForSentence (SentenceSortSentence sentence)
definedNamesForSentence (SentenceHookSentence (SentenceHookedSymbol sentence)) =
    definedNamesForSentence (SentenceSymbolSentence sentence)

newtype SortIndex =
    SortIndex { sorts :: Map Id Verified.SentenceSort }

data SymbolIndex =
    SymbolIndex
        { symbolSorts :: Map Id Verified.SentenceSort
        , symbols :: Map Id Verified.SentenceSymbol
        }

data AliasIndex =
    AliasIndex
        { aliasSorts :: Map Id Verified.SentenceSort
        , aliasSymbols :: Map Id Verified.SentenceSymbol
        , aliases :: Map Id Verified.SentenceAlias
        }

data RuleIndex =
    RuleIndex
        { ruleSorts :: Map Id Verified.SentenceSort
        , ruleSymbols :: Map Id Verified.SentenceSymbol
        , ruleAliases :: Map Id Verified.SentenceAlias
        , claims :: [Verified.SentenceClaim]
        , axioms :: [Verified.SentenceAxiom]
        }

verifySentencesNEW
    :: KoreIndexedModule Attribute.Symbol axiomAtts
    -> Builtin.Verifiers
    -> Either (Error VerifyError) [Verified.Sentence]
verifySentencesNEW indexedModule builtinVerifiers = do
    let rawSorts =
            snd
            <$> indexedModuleSortDescriptions indexedModule
        rawSymbols =
            snd
            <$> indexedModuleSymbolSentences indexedModule
        rawAliases =
            snd
            <$> indexedModuleAliasSentences indexedModule
        rawClaims =
            snd
            <$> indexedModuleClaims indexedModule
        rawAxioms =
            snd
            <$> indexedModuleAxioms indexedModule
    sortIndex <- verifySorts rawSorts
    symbolIndex <-
        verifySymbols
            indexedModule
            sortIndex
            rawSymbols
    aliasIndex <-
        verifyAliases
            symbolIndex
            builtinVerifiers
            indexedModule
            rawAliases
    ruleIndex <-
        verifyRules
            aliasIndex
            builtinVerifiers
            indexedModule
            rawClaims
            rawAxioms
    pure . getVerifiedSentences $ ruleIndex

getVerifiedSentences :: RuleIndex -> [Verified.Sentence]
getVerifiedSentences ruleIndex =
    (SentenceSortSentence <$> Map.elems verifiedSorts)
    <> (SentenceSymbolSentence <$> Map.elems verifiedSymbols)
    <> (SentenceAliasSentence <$> Map.elems verifiedAliases)
    <> (SentenceClaimSentence <$> verifiedClaims)
    <> (SentenceAxiomSentence <$> verifiedAxioms)
  where
    verifiedSorts = ruleSorts ruleIndex
    verifiedSymbols = ruleSymbols ruleIndex
    verifiedAliases = ruleAliases ruleIndex
    verifiedClaims = claims ruleIndex
    verifiedAxioms = axioms ruleIndex

verifySorts
    :: Map Id ParsedSentenceSort
    -> Either (Error VerifyError) SortIndex
verifySorts rawSorts = do
    SortIndex <$> traverse verifySortWithContext rawSorts
  where
    verifySortWithContext sort =
        withSentenceSortContext sort (verifySortSentence sort)

verifySymbols
    :: KoreIndexedModule declAtts axiomAtts
    -> SortIndex
    -> Map Id ParsedSentenceSymbol
    -> Either (Error VerifyError) SymbolIndex
verifySymbols indexedModule sortIndex rawSymbols = do
    verifiedSymbols <-
        traverse verifySymbolWithContext rawSymbols
    pure SymbolIndex
        { symbolSorts = sorts sortIndex
        , symbols = verifiedSymbols
        }
  where
    verifySymbolWithContext symbol =
        withSentenceSymbolContext
            symbol
            (verifySymbolSentenceNEW indexedModule sortIndex symbol)

verifySymbolSentenceNEW
    :: KoreIndexedModule declAtts axiomAtts
    -> SortIndex
    -> ParsedSentenceSymbol
    -> Either (Error VerifyError) Verified.SentenceSymbol
verifySymbolSentenceNEW indexedModule sortIndex sentence =
    do
        variables <- buildDeclaredSortVariables sortParams
        mapM_
            (verifySort findSort variables)
            (sentenceSymbolSorts sentence)
        verifyConstructorNotInHookedOrDvSort
        verifySort
            findSort
            variables
            (sentenceSymbolResultSort sentence)
        traverse verifyNoPatterns sentence
  where
    -- findSort :: Id -> Either (Error VerifyError) Verified.SentenceSort
    -- findSort sortId =
    --     maybe
    --         (koreFailWithLocations [sortId] $ noSortText sortId)
    --         pure
    --         $ Map.lookup sortId (sorts sortIndex)

    findSort = findIndexedSort indexedModule
    sortParams = (symbolParams . sentenceSymbolSymbol) sentence

    verifyConstructorNotInHookedOrDvSort :: Either (Error VerifyError) ()
    verifyConstructorNotInHookedOrDvSort =
        let
            symbol = symbolConstructor $ sentenceSymbolSymbol sentence
            attributes = sentenceSymbolAttributes sentence
            resultSort = sentenceSymbolResultSort sentence
            resultSortId = getSortId resultSort

            -- TODO(vladimir.ciobanu): Lookup this attribute in the symbol
            -- attribute record when it becomes available.
            isCtor =
                Attribute.constructorAttribute `elem` getAttributes attributes
            sortData = do
                (sortDescription, _) <-
                    Map.lookup resultSortId
                        $ indexedModuleSortDescriptions indexedModule
                return
                    (maybeHook sortDescription, hasDomainValues sortDescription)
        in case sortData of
            Nothing -> return ()
            Just (resultSortHook, resultHasDomainValues) -> do
                koreFailWhen
                    (isCtor && isJust resultSortHook)
                    ( "Cannot define constructor '"
                    ++ getIdForError symbol
                    ++ "' for hooked sort '"
                    ++ getIdForError resultSortId
                    ++ "'."
                    )
                koreFailWhen
                    (isCtor && resultHasDomainValues)
                    (noConstructorWithDomainValuesMessage symbol resultSort)

verifyAliases
    :: SymbolIndex
    -> Builtin.Verifiers
    -> KoreIndexedModule Attribute.Symbol axiomAtts
    -> Map Id ParsedSentenceAlias
    -> Either (Error VerifyError) AliasIndex
verifyAliases symbolIndex builtinVerifiers indexedModule rawAliases = do
    verifiedAliases <-
        traverse
            verifyAliasWithContext
            rawAliases
    pure AliasIndex
        { aliasSorts = symbolSorts symbolIndex
        , aliasSymbols = symbols symbolIndex
        , aliases = verifiedAliases
        }
  where
    verifyAliasWithContext alias =
        withSentenceAliasContext
            alias
            (verifyAliasSentenceNEW builtinVerifiers symbolIndex indexedModule alias)

verifyAliasSentenceNEW
    :: Builtin.Verifiers
    -> SymbolIndex
    -> KoreIndexedModule Attribute.Symbol axiomAtts
    -> ParsedSentenceAlias
    -> Either (Error VerifyError) Verified.SentenceAlias
verifyAliasSentenceNEW builtinVerifiers symbolIndex indexedModule sentence =
    do
        variables <- buildDeclaredSortVariables sortParams
        mapM_ (verifySort findSort variables) sentenceAliasSorts
        verifySort findSort variables sentenceAliasResultSort
        let context =
                PatternVerifier.Context
                    { builtinDomainValueVerifiers =
                        Builtin.domainValueVerifiers builtinVerifiers
                    , indexedModule =
                        IndexedModule.eraseAxiomAttributes
                        $ IndexedModule.erasePatterns indexedModule
                    , declaredSortVariables = variables
                    , declaredVariables = emptyDeclaredVariables
                    }
        runPatternVerifier context $ do
            (declaredVariables, verifiedLeftPattern) <-
                verifyAliasLeftPattern leftPattern
            verifiedRightPattern <-
                withDeclaredVariables declaredVariables
                $ verifyPattern (Just expectedSort) rightPattern
            return sentence
                { sentenceAliasLeftPattern = verifiedLeftPattern
                , sentenceAliasRightPattern = verifiedRightPattern
                }
  where
    SentenceAlias { sentenceAliasLeftPattern = leftPattern } = sentence
    SentenceAlias { sentenceAliasRightPattern = rightPattern } = sentence
    SentenceAlias { sentenceAliasSorts } = sentence
    SentenceAlias { sentenceAliasResultSort } = sentence

    findSort = findIndexedSort indexedModule

    -- findSort :: Id -> Either (Error VerifyError) Verified.SentenceSort
    -- findSort sortId =
    --     maybe
    --         (koreFailWithLocations [sortId] $ noSortText sortId)
    --         pure
    --         $ Map.lookup sortId (symbolSorts symbolIndex)

    sortParams   = (aliasParams . sentenceAliasAlias) sentence
    expectedSort = sentenceAliasResultSort

verifyRules
    :: AliasIndex
    -> Builtin.Verifiers
    -> KoreIndexedModule Attribute.Symbol axiomAtts
    -> [SentenceClaim ParsedPattern]
    -> [SentenceAxiom ParsedPattern]
    -> Either (Error VerifyError) RuleIndex
verifyRules aliasIndex builtinVerifiers indexedModule rawClaims rawAxioms = do
    verifiedClaims <- traverse verifyClaimWithContext rawClaims
    verifiedAxioms <- traverse verifyAxiomWithContext rawAxioms
    pure RuleIndex
        { ruleSorts = aliasSorts aliasIndex
        , ruleSymbols = aliasSymbols aliasIndex
        , ruleAliases = aliases aliasIndex
        , claims = verifiedClaims
        , axioms = verifiedAxioms
        }
  where
    verifyClaim (SentenceClaim axiom) =
        SentenceClaim
        <$> verifyAxiomSentenceNEW
            axiom aliasIndex builtinVerifiers indexedModule

    verifyClaimWithContext claim =
        withSentenceClaimContext
            claim
            (verifyClaim claim)

    verifyAxiomWithContext axiom =
        withSentenceAxiomContext
            axiom
            (verifyAxiomSentenceNEW
                axiom aliasIndex builtinVerifiers indexedModule)

verifyAxiomSentenceNEW
    :: ParsedSentenceAxiom
    -> AliasIndex
    -> Builtin.Verifiers
    -> KoreIndexedModule Attribute.Symbol axiomAtts
    -> Either (Error VerifyError) Verified.SentenceAxiom
verifyAxiomSentenceNEW axiom aliasIndex builtinVerifiers indexedModule =
    do
        variables <- buildDeclaredSortVariables $ sentenceAxiomParameters axiom
        let context =
                PatternVerifier.Context
                    { builtinDomainValueVerifiers =
                        Builtin.domainValueVerifiers builtinVerifiers
                    , indexedModule =
                        indexedModule
                        & IndexedModule.erasePatterns
                        & IndexedModule.eraseAxiomAttributes
                    , declaredSortVariables = variables
                    , declaredVariables = emptyDeclaredVariables
                    }
        verifiedAxiomPattern <- runPatternVerifier context $
            verifyStandalonePattern Nothing sentenceAxiomPattern
        return axiom { sentenceAxiomPattern = verifiedAxiomPattern }
  where
    SentenceAxiom { sentenceAxiomPattern } = axiom

-- TODO: remove
{-|'verifySentences' verifies the welformedness of a list of Kore 'Sentence's.
-}
verifySentences
    :: KoreIndexedModule Attribute.Symbol axiomAtts
    -- ^ The module containing all definitions which are visible in this
    -- pattern.
    -> AttributesVerification Attribute.Symbol axiomAtts
    -> Builtin.Verifiers
    -> [ParsedSentence]
    -> Either (Error VerifyError) [Verified.Sentence]
verifySentences indexedModule attributesVerification builtinVerifiers =
    traverse
        (verifySentence
            builtinVerifiers
            indexedModule
            attributesVerification
        )

verifySentence
    :: Builtin.Verifiers
    -> KoreIndexedModule Attribute.Symbol axiomAtts
    -> AttributesVerification Attribute.Symbol axiomAtts
    -> ParsedSentence
    -> Either (Error VerifyError) Verified.Sentence
verifySentence builtinVerifiers indexedModule attributesVerification sentence =
    withSentenceContext sentence verifySentenceWorker
  where
    verifySentenceWorker :: Either (Error VerifyError) Verified.Sentence
    verifySentenceWorker = do
        verified <-
            case sentence of
                SentenceSymbolSentence symbolSentence ->
                    (<$>)
                        SentenceSymbolSentence
                        (verifySymbolSentence
                            indexedModule
                            symbolSentence
                        )
                SentenceAliasSentence aliasSentence ->
                    (<$>)
                        SentenceAliasSentence
                        (verifyAliasSentence
                            builtinVerifiers
                            indexedModule
                            aliasSentence
                        )
                SentenceAxiomSentence axiomSentence ->
                    (<$>)
                        SentenceAxiomSentence
                        (verifyAxiomSentence
                            axiomSentence
                            builtinVerifiers
                            indexedModule
                        )
                SentenceClaimSentence claimSentence ->
                    (<$>)
                        (SentenceClaimSentence . SentenceClaim)
                        (verifyAxiomSentence
                            (getSentenceClaim claimSentence)
                            builtinVerifiers
                            indexedModule
                        )
                SentenceImportSentence importSentence ->
                    -- Since we have an IndexedModule, we assume that imports
                    -- were already resolved, so there is nothing left to verify
                    -- here.
                    (<$>)
                        SentenceImportSentence
                        (traverse verifyNoPatterns importSentence)
                SentenceSortSentence sortSentence ->
                    (<$>)
                        SentenceSortSentence
                        (verifySortSentence sortSentence)
                SentenceHookSentence hookSentence ->
                    (<$>)
                        SentenceHookSentence
                        (verifyHookSentence
                            builtinVerifiers
                            indexedModule
                            attributesVerification
                            hookSentence
                        )
        verifySentenceAttributes
            attributesVerification
            sentence
        return verified

verifySentenceAttributes
    :: AttributesVerification declAtts axiomAtts
    -> ParsedSentence
    -> Either (Error VerifyError) VerifySuccess
verifySentenceAttributes attributesVerification sentence =
    do
        let attributes = sentenceAttributes sentence
        verifyAttributes attributes attributesVerification
        case sentence of
            SentenceHookSentence _ -> return ()
            _ -> verifyNoHookAttribute attributesVerification attributes
        verifySuccess

verifyHookSentence
    :: Builtin.Verifiers
    -> KoreIndexedModule declAtts axiomAtts
    -> AttributesVerification declAtts axiomAtts
    -> ParsedSentenceHook
    -> Either (Error VerifyError) Verified.SentenceHook
verifyHookSentence
    builtinVerifiers
    indexedModule
    attributesVerification
  =
    \case
        SentenceHookedSort s -> SentenceHookedSort <$> verifyHookedSort s
        SentenceHookedSymbol s -> SentenceHookedSymbol <$> verifyHookedSymbol s
  where
    verifyHookedSort
        sentence@SentenceSort { sentenceSortAttributes }
      = do
        verified <- verifySortSentence sentence
        hook <-
            verifySortHookAttribute
                indexedModule
                attributesVerification
                sentenceSortAttributes
        attrs <-
            Attribute.Parser.liftParser
            $ Attribute.Parser.parseAttributes sentenceSortAttributes
        Builtin.sortDeclVerifier
            builtinVerifiers
            hook
            (IndexedModule.eraseAttributes indexedModule)
            sentence
            attrs
        return verified

    verifyHookedSymbol
        sentence@SentenceSymbol { sentenceSymbolAttributes }
      = do
        verified <- verifySymbolSentence indexedModule sentence
        hook <-
            verifySymbolHookAttribute
                attributesVerification
                sentenceSymbolAttributes
        Builtin.runSymbolVerifier
            (Builtin.symbolVerifier builtinVerifiers hook) findSort sentence
        return verified

    findSort = findIndexedSort indexedModule

verifySymbolSentence
    :: KoreIndexedModule declAtts axiomAtts
    -> ParsedSentenceSymbol
    -> Either (Error VerifyError) Verified.SentenceSymbol
verifySymbolSentence indexedModule sentence =
    do
        variables <- buildDeclaredSortVariables sortParams
        mapM_
            (verifySort findSort variables)
            (sentenceSymbolSorts sentence)
        verifyConstructorNotInHookedOrDvSort
        verifySort
            findSort
            variables
            (sentenceSymbolResultSort sentence)
        traverse verifyNoPatterns sentence
  where
    findSort = findIndexedSort indexedModule
    sortParams = (symbolParams . sentenceSymbolSymbol) sentence

    verifyConstructorNotInHookedOrDvSort :: Either (Error VerifyError) ()
    verifyConstructorNotInHookedOrDvSort =
        let
            symbol = symbolConstructor $ sentenceSymbolSymbol sentence
            attributes = sentenceSymbolAttributes sentence
            resultSort = sentenceSymbolResultSort sentence
            resultSortId = getSortId resultSort

            -- TODO(vladimir.ciobanu): Lookup this attribute in the symbol
            -- attribute record when it becomes available.
            isCtor =
                Attribute.constructorAttribute  `elem` getAttributes attributes
            sortData = do
                (sortDescription, _) <-
                    Map.lookup resultSortId
                        $ indexedModuleSortDescriptions indexedModule
                return
                    (maybeHook sortDescription, hasDomainValues sortDescription)
        in case sortData of
            Nothing -> return ()
            Just (resultSortHook, resultHasDomainValues) -> do
                koreFailWhen
                    (isCtor && isJust resultSortHook)
                    ( "Cannot define constructor '"
                    ++ getIdForError symbol
                    ++ "' for hooked sort '"
                    ++ getIdForError resultSortId
                    ++ "'."
                    )
                koreFailWhen
                    (isCtor && resultHasDomainValues)
                    (noConstructorWithDomainValuesMessage symbol resultSort)

maybeHook :: Attribute.Sort -> Maybe Text
maybeHook = Attribute.getHook . Attribute.Sort.hook

hasDomainValues :: Attribute.Sort -> Bool
hasDomainValues =
    Attribute.HasDomainValues.getHasDomainValues
    . Attribute.Sort.hasDomainValues

verifyAliasSentence
    :: Builtin.Verifiers
    -> KoreIndexedModule Attribute.Symbol axiomAtts
    -> ParsedSentenceAlias
    -> Either (Error VerifyError) Verified.SentenceAlias
verifyAliasSentence builtinVerifiers indexedModule sentence =
    do
        variables <- buildDeclaredSortVariables sortParams
        mapM_ (verifySort findSort variables) sentenceAliasSorts
        verifySort findSort variables sentenceAliasResultSort
        let context =
                PatternVerifier.Context
                    { builtinDomainValueVerifiers =
                        Builtin.domainValueVerifiers builtinVerifiers
                    , indexedModule =
                        IndexedModule.eraseAxiomAttributes
                        $ IndexedModule.erasePatterns indexedModule
                    , declaredSortVariables = variables
                    , declaredVariables = emptyDeclaredVariables
                    }
        runPatternVerifier context $ do
            (declaredVariables, verifiedLeftPattern) <-
                verifyAliasLeftPattern leftPattern
            verifiedRightPattern <-
                withDeclaredVariables declaredVariables
                $ verifyPattern (Just expectedSort) rightPattern
            return sentence
                { sentenceAliasLeftPattern = verifiedLeftPattern
                , sentenceAliasRightPattern = verifiedRightPattern
                }
  where
    SentenceAlias { sentenceAliasLeftPattern = leftPattern } = sentence
    SentenceAlias { sentenceAliasRightPattern = rightPattern } = sentence
    SentenceAlias { sentenceAliasSorts } = sentence
    SentenceAlias { sentenceAliasResultSort } = sentence
    findSort     = findIndexedSort indexedModule
    sortParams   = (aliasParams . sentenceAliasAlias) sentence
    expectedSort = sentenceAliasResultSort

verifyAxiomSentence
    :: ParsedSentenceAxiom
    -> Builtin.Verifiers
    -> KoreIndexedModule Attribute.Symbol axiomAtts
    -> Either (Error VerifyError) Verified.SentenceAxiom
verifyAxiomSentence axiom builtinVerifiers indexedModule =
    do
        variables <- buildDeclaredSortVariables $ sentenceAxiomParameters axiom
        let context =
                PatternVerifier.Context
                    { builtinDomainValueVerifiers =
                        Builtin.domainValueVerifiers builtinVerifiers
                    , indexedModule =
                        indexedModule
                        & IndexedModule.erasePatterns
                        & IndexedModule.eraseAxiomAttributes
                    , declaredSortVariables = variables
                    , declaredVariables = emptyDeclaredVariables
                    }
        verifiedAxiomPattern <- runPatternVerifier context $
            verifyStandalonePattern Nothing sentenceAxiomPattern
        return axiom { sentenceAxiomPattern = verifiedAxiomPattern }
  where
    SentenceAxiom { sentenceAxiomPattern } = axiom

verifySortSentence
    :: ParsedSentenceSort
    -> Either (Error VerifyError) Verified.SentenceSort
verifySortSentence sentenceSort = do
    _ <- buildDeclaredSortVariables (sentenceSortParameters sentenceSort)
    traverse verifyNoPatterns sentenceSort

buildDeclaredSortVariables
    :: [SortVariable]
    -> Either (Error VerifyError) (Set.Set SortVariable)
buildDeclaredSortVariables [] = Right Set.empty
buildDeclaredSortVariables (unifiedVariable : list) = do
    variables <- buildDeclaredSortVariables list
    koreFailWithLocationsWhen
        (unifiedVariable `Set.member` variables)
        [unifiedVariable]
        (  "Duplicated sort variable: '"
        <> extractVariableName unifiedVariable
        <> "'.")
    return (Set.insert unifiedVariable variables)
  where
    extractVariableName variable = getId (getSortVariable variable)
