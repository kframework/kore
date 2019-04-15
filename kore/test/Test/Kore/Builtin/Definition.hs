module Test.Kore.Builtin.Definition where

import qualified Data.Map.Strict as Map
import qualified Data.Sequence as Seq
import qualified Data.Set as Set
import           Data.Text
                 ( Text )

import           Kore.AST.Kore
import           Kore.AST.Sentence
import           Kore.AST.Valid
import           Kore.Attribute.Constructor
import           Kore.Attribute.Functional
import           Kore.Attribute.Hook
import           Kore.Attribute.Injective
import           Kore.Attribute.Smthook
import           Kore.Attribute.Smtlib
import qualified Kore.Attribute.Sort.Concat as Sort
import qualified Kore.Attribute.Sort.Element as Sort
import qualified Kore.Attribute.Sort.Unit as Sort
import qualified Kore.Builtin.Set as Set
import           Kore.Domain.Builtin
import           Kore.Step.Pattern

import Test.Kore

-- -------------------------------------------------------------
-- * Builtin symbols

-- | Make an unparameterized builtin symbol with the given name.
builtinSymbol :: Text -> SymbolOrAlias Object
builtinSymbol name =
    SymbolOrAlias
        { symbolOrAliasConstructor = testId name
        , symbolOrAliasParams = []
        }

-- ** Bool

orBoolSymbol :: SymbolOrAlias Object
orBoolSymbol = builtinSymbol "orBool"

orElseBoolSymbol :: SymbolOrAlias Object
orElseBoolSymbol = builtinSymbol "orElseBool"

andBoolSymbol :: SymbolOrAlias Object
andBoolSymbol = builtinSymbol "andBool"

andThenBoolSymbol :: SymbolOrAlias Object
andThenBoolSymbol = builtinSymbol "andThenBool"

xorBoolSymbol :: SymbolOrAlias Object
xorBoolSymbol = builtinSymbol "xorBool"

neBoolSymbol :: SymbolOrAlias Object
neBoolSymbol = builtinSymbol "neBool"

eqBoolSymbol :: SymbolOrAlias Object
eqBoolSymbol = builtinSymbol "eqBool"

notBoolSymbol :: SymbolOrAlias Object
notBoolSymbol = builtinSymbol "notBool"

impliesBoolSymbol :: SymbolOrAlias Object
impliesBoolSymbol = builtinSymbol "impliesBool"

-- ** Int

gtIntSymbol :: SymbolOrAlias Object
gtIntSymbol = builtinSymbol "gtInt"

geIntSymbol :: SymbolOrAlias Object
geIntSymbol = builtinSymbol "geInt"

eqIntSymbol :: SymbolOrAlias Object
eqIntSymbol = builtinSymbol "eqInt"

leIntSymbol :: SymbolOrAlias Object
leIntSymbol = builtinSymbol "leInt"

ltIntSymbol :: SymbolOrAlias Object
ltIntSymbol = builtinSymbol "ltInt"

neIntSymbol :: SymbolOrAlias Object
neIntSymbol = builtinSymbol "neInt"

minIntSymbol :: SymbolOrAlias Object
minIntSymbol = builtinSymbol "minInt"

maxIntSymbol :: SymbolOrAlias Object
maxIntSymbol = builtinSymbol "maxInt"

addIntSymbol :: SymbolOrAlias Object
addIntSymbol = builtinSymbol "addInt"

subIntSymbol :: SymbolOrAlias Object
subIntSymbol = builtinSymbol "subInt"

mulIntSymbol :: SymbolOrAlias Object
mulIntSymbol = builtinSymbol "mulInt"

absIntSymbol :: SymbolOrAlias Object
absIntSymbol = builtinSymbol "absInt"

tdivIntSymbol :: SymbolOrAlias Object
tdivIntSymbol = builtinSymbol "tdivInt"

tmodIntSymbol :: SymbolOrAlias Object
tmodIntSymbol = builtinSymbol "tmodInt"

andIntSymbol :: SymbolOrAlias Object
andIntSymbol = builtinSymbol "andInt"

orIntSymbol :: SymbolOrAlias Object
orIntSymbol = builtinSymbol "orInt"

xorIntSymbol :: SymbolOrAlias Object
xorIntSymbol = builtinSymbol "xorInt"

notIntSymbol :: SymbolOrAlias Object
notIntSymbol = builtinSymbol "notInt"

shlIntSymbol :: SymbolOrAlias Object
shlIntSymbol = builtinSymbol "shlInt"

shrIntSymbol :: SymbolOrAlias Object
shrIntSymbol = builtinSymbol "shrInt"

powIntSymbol :: SymbolOrAlias Object
powIntSymbol = builtinSymbol "powInt"

powmodIntSymbol :: SymbolOrAlias Object
powmodIntSymbol = builtinSymbol "powmodInt"

log2IntSymbol :: SymbolOrAlias Object
log2IntSymbol = builtinSymbol "log2Int"

emodIntSymbol :: SymbolOrAlias Object
emodIntSymbol = builtinSymbol "emodInt"

-- an unhooked, uninterpreted function f : Int -> Int
dummyIntSymbol :: SymbolOrAlias Object
dummyIntSymbol = builtinSymbol "f"

-- ** KEQUAL

keqBoolSymbol :: SymbolOrAlias Object
keqBoolSymbol = builtinSymbol "keqBool"

kneqBoolSymbol :: SymbolOrAlias Object
kneqBoolSymbol = builtinSymbol "kneqBool"

kiteKSymbol :: SymbolOrAlias Object
kiteKSymbol = builtinSymbol "kiteK"

kseqSymbol :: SymbolOrAlias Object
kseqSymbol = builtinSymbol "kseq"

dotkSymbol :: SymbolOrAlias Object
dotkSymbol = builtinSymbol "dotk"

injSymbol :: Sort Object -> Sort Object -> SymbolOrAlias Object
injSymbol lSort rSort =
    SymbolOrAlias
        { symbolOrAliasConstructor = testId "inj"
        , symbolOrAliasParams = [lSort, rSort]
        }

-- ** List

unitListSymbol :: SymbolOrAlias Object
unitListSymbol = builtinSymbol "unitList"

unitList2Symbol :: SymbolOrAlias Object
unitList2Symbol = builtinSymbol "unitList2"

elementListSymbol :: SymbolOrAlias Object
elementListSymbol = builtinSymbol "elementList"

elementList2Symbol :: SymbolOrAlias Object
elementList2Symbol = builtinSymbol "elementList2"

concatListSymbol :: SymbolOrAlias Object
concatListSymbol = builtinSymbol "concatList"

concatList2Symbol :: SymbolOrAlias Object
concatList2Symbol = builtinSymbol "concatList2"

getListSymbol :: SymbolOrAlias Object
getListSymbol = builtinSymbol "getList"

-- ** Map

unitMapSymbol :: SymbolOrAlias Object
unitMapSymbol = builtinSymbol "unitMap"

updateMapSymbol :: SymbolOrAlias Object
updateMapSymbol = builtinSymbol "updateMap"

lookupMapSymbol :: SymbolOrAlias Object
lookupMapSymbol = builtinSymbol "lookupMap"

elementMapSymbol :: SymbolOrAlias Object
elementMapSymbol = builtinSymbol "elementMap"

concatMapSymbol :: SymbolOrAlias Object
concatMapSymbol = builtinSymbol "concatMap"

inKeysMapSymbol :: SymbolOrAlias Object
inKeysMapSymbol = builtinSymbol "inKeysMap"

keysMapSymbol :: SymbolOrAlias Object
keysMapSymbol = builtinSymbol "keysMap"

unitMap :: CommonStepPattern Object
unitMap = mkApp mapSort unitMapSymbol []

updateMap
    :: CommonStepPattern Object
    -> CommonStepPattern Object
    -> CommonStepPattern Object
    -> CommonStepPattern Object
updateMap map' key value =
    mkApp mapSort updateMapSymbol [map', key, value]

lookupMap
    :: CommonStepPattern Object
    -> CommonStepPattern Object
    -> CommonStepPattern Object
lookupMap map' key =
    mkApp intSort lookupMapSymbol [map', key]

elementMap
    :: CommonStepPattern Object
    -> CommonStepPattern Object
    -> CommonStepPattern Object
elementMap key value =
    mkApp mapSort elementMapSymbol [key, value]

concatMap
    :: CommonStepPattern Object
    -> CommonStepPattern Object
    -> CommonStepPattern Object
concatMap map1 map2 =
    mkApp mapSort concatMapSymbol [map1, map2]

inKeysMap
    :: CommonStepPattern Object
    -> CommonStepPattern Object
    -> CommonStepPattern Object
inKeysMap key map' =
    mkApp boolSort inKeysMapSymbol [key, map']

keysMap
    :: CommonStepPattern Object
    -> CommonStepPattern Object
keysMap map' =
    mkApp setSort keysMapSymbol [map']

-- ** Pair

pairSymbol :: Sort Object -> Sort Object -> SymbolOrAlias Object
pairSymbol lSort rSort =
    SymbolOrAlias
        { symbolOrAliasConstructor = testId "pair"
        , symbolOrAliasParams = [lSort, rSort]
        }

-- ** Set

unitSetSymbol :: SymbolOrAlias Object
unitSetSymbol = builtinSymbol "unitSet"

elementSetSymbol :: SymbolOrAlias Object
elementSetSymbol = builtinSymbol "elementSet"

concatSetSymbol :: SymbolOrAlias Object
concatSetSymbol = builtinSymbol "concatSet"

inSetSymbol :: SymbolOrAlias Object
inSetSymbol = builtinSymbol "inSet"

differenceSetSymbol :: SymbolOrAlias Object
differenceSetSymbol = builtinSymbol "differenceSet"

toListSetSymbol :: SymbolOrAlias Object
toListSetSymbol = builtinSymbol "toListSet"

sizeSetSymbol :: SymbolOrAlias Object
sizeSetSymbol = builtinSymbol "sizeSet"

-- ** String

ltStringSymbol :: SymbolOrAlias Object
ltStringSymbol = builtinSymbol "ltString"

concatStringSymbol :: SymbolOrAlias Object
concatStringSymbol = builtinSymbol "concatString"

substrStringSymbol :: SymbolOrAlias Object
substrStringSymbol = builtinSymbol "substrString"

lengthStringSymbol :: SymbolOrAlias Object
lengthStringSymbol = builtinSymbol "lengthString"

chrStringSymbol :: SymbolOrAlias Object
chrStringSymbol = builtinSymbol "chrString"

ordStringSymbol :: SymbolOrAlias Object
ordStringSymbol = builtinSymbol "ordString"

findStringSymbol :: SymbolOrAlias Object
findStringSymbol = builtinSymbol "findString"

string2BaseStringSymbol :: SymbolOrAlias Object
string2BaseStringSymbol = builtinSymbol "string2baseString"

string2IntStringSymbol :: SymbolOrAlias Object
string2IntStringSymbol = builtinSymbol "string2intString"

ecdsaRecoverSymbol :: SymbolOrAlias Object
ecdsaRecoverSymbol = builtinSymbol "ECDSARecover"

keccakSymbol :: SymbolOrAlias Object
keccakSymbol = builtinSymbol "KECCAK"

-- -------------------------------------------------------------
-- * Sorts

-- | Declare 'a sort' in a Kore module.
sortDecl :: Sort Object -> KoreSentence
sortDecl sort =
    asSentence sentence
  where
    sentence :: KoreSentenceSort Object
    sentence =
        SentenceSort
            { sentenceSortName =
                let SortActualSort SortActual { sortActualName } = sort
                in sortActualName
            , sentenceSortParameters = []
            , sentenceSortAttributes = Attributes []
            }

-- | Declare a hooked sort.
hookedSortDecl
    :: Sort Object
    -- ^ declared sort
    -> [CommonKorePattern]
    -- ^ declaration attributes
    -> KoreSentence
hookedSortDecl sort attrs =
    (asSentence . SentenceHookedSort) sentence
  where
    sentence :: KoreSentenceSort Object
    sentence =
        SentenceSort
            { sentenceSortName =
                let SortActualSort SortActual { sortActualName } = sort
                in sortActualName
            , sentenceSortParameters = []
            , sentenceSortAttributes = Attributes attrs
            }

-- ** Bool

-- | A sort to hook to the builtin @BOOL.Bool@.
boolSort :: Sort Object
boolSort =
    SortActualSort SortActual
        { sortActualName = testId "Bool"
        , sortActualSorts = []
        }

-- | Declare 'boolSort' in a Kore module.
boolSortDecl :: KoreSentence
boolSortDecl = hookedSortDecl boolSort [ hookAttribute "BOOL.Bool" ]

builtinBool :: Bool -> InternalBool
builtinBool builtinBoolValue =
    InternalBool
        { builtinBoolSort = boolSort
        , builtinBoolValue
        }

-- ** Int

-- | A sort to hook to the builtin @INT.Int@.
intSort :: Sort Object
intSort =
    SortActualSort SortActual
        { sortActualName = testId "Int"
        , sortActualSorts = []
        }

-- | Declare 'intSort' in a Kore module.
intSortDecl :: KoreSentence
intSortDecl = hookedSortDecl intSort [ hookAttribute "INT.Int" ]

builtinInt :: Integer -> InternalInt
builtinInt builtinIntValue =
    InternalInt
        { builtinIntSort = intSort
        , builtinIntValue
        }

-- ** KEQUAL

kSort :: Sort Object
kSort =
    SortActualSort SortActual
        { sortActualName = testId "SortK"
        , sortActualSorts = []
        }

kItemSort :: Sort Object
kItemSort =
    SortActualSort SortActual
        { sortActualName = testId "SortKItem"
        , sortActualSorts = []
        }

idSort :: Sort Object
idSort =
    SortActualSort SortActual
        { sortActualName = testId "SortId"
        , sortActualSorts = []
        }


-- ** List

-- | A sort to hook to the builtin @LIST.List@.
listSort :: Sort Object
listSort =
    SortActualSort SortActual
        { sortActualName = testId "List"
        , sortActualSorts = []
        }

-- | Declare 'listSort' in a Kore module.
listSortDecl :: KoreSentence
listSortDecl =
    hookedSortDecl
        listSort
        [ hookAttribute "LIST.List"
        , Sort.unitAttribute unitListSymbol
        , Sort.elementAttribute elementListSymbol
        , Sort.concatAttribute concatListSymbol
        ]

builtinList
    :: [CommonStepPattern Object]
    -> InternalList (CommonStepPattern Object)
builtinList children =
    InternalList
        { builtinListSort = listSort
        , builtinListUnit = unitListSymbol
        , builtinListElement = elementListSymbol
        , builtinListConcat = concatListSymbol
        , builtinListChild = Seq.fromList children
        }

-- | Another sort with the same hook
listSort2 :: Sort Object
listSort2 =
    SortActualSort SortActual
        { sortActualName = testId "List2"
        , sortActualSorts = []
        }

-- | Declare 'listSort' in a Kore module.
listSortDecl2 :: KoreSentence
listSortDecl2 =
    hookedSortDecl
        listSort2
        [ hookAttribute "LIST.List"
        , Sort.unitAttribute unitList2Symbol
        , Sort.elementAttribute elementList2Symbol
        , Sort.concatAttribute concatList2Symbol
        ]

-- ** Map

-- | A sort to hook to the builtin @MAP.Map@.
mapSort :: Sort Object
mapSort =
    SortActualSort SortActual
        { sortActualName = testId "Map"
        , sortActualSorts = []
        }

-- | Declare 'mapSort' in a Kore module.
mapSortDecl :: KoreSentence
mapSortDecl =
    hookedSortDecl
        mapSort
        [ hookAttribute "MAP.Map"
        , Sort.unitAttribute unitMapSymbol
        , Sort.elementAttribute elementMapSymbol
        , Sort.concatAttribute concatMapSymbol
        ]

builtinMap
    :: [(ConcreteStepPattern Object, CommonStepPattern Object)]
    -> InternalMap (CommonStepPattern Object)
builtinMap children =
    InternalMap
        { builtinMapSort = mapSort
        , builtinMapUnit = unitMapSymbol
        , builtinMapElement = elementMapSymbol
        , builtinMapConcat = concatMapSymbol
        , builtinMapChild = Map.fromList children
        }

-- ** Pair

pairSort :: Sort Object -> Sort Object -> Sort Object
pairSort lSort rSort =
    SortActualSort SortActual
        { sortActualName = testId "Pair"
        , sortActualSorts = [lSort, rSort]
        }

-- | Declare 'Pair' in a Kore module.
pairSortDecl :: KoreSentence
pairSortDecl =
    asSentence decl
  where
    lSortVariable = SortVariable (testId "l")
    rSortVariable = SortVariable (testId "r")
    lSort = SortVariableSort lSortVariable
    rSort = SortVariableSort rSortVariable
    decl :: KoreSentenceSort Object
    decl =
        SentenceSort
            { sentenceSortName =
                let SortActualSort SortActual { sortActualName } =
                        pairSort lSort rSort
                in sortActualName
            , sentenceSortParameters = [lSortVariable, rSortVariable]
            , sentenceSortAttributes = Attributes []
            }

-- ** Set

-- | A sort to hook to the builtin @SET.Set@.
setSort :: Sort Object
setSort =
    SortActualSort SortActual
        { sortActualName = testId "Set"
        , sortActualSorts = []
        }

-- | Declare 'setSort' in a Kore module.
setSortDecl :: KoreSentence
setSortDecl =
    hookedSortDecl
        setSort
        [ hookAttribute "SET.Set"
        , Sort.unitAttribute unitSetSymbol
        , Sort.elementAttribute elementSetSymbol
        , Sort.concatAttribute concatSetSymbol
        ]

builtinSet
    :: [ConcreteStepPattern Object]
    -> InternalSet
builtinSet children =
    InternalSet
        { builtinSetSort = setSort
        , builtinSetUnit = unitSetSymbol
        , builtinSetElement = elementSetSymbol
        , builtinSetConcat = concatSetSymbol
        , builtinSetChild = Set.fromList children
        }

-- ** String

-- | A sort to hook to the builtin @STRING.String@.
stringSort :: Sort Object
stringSort =
    SortActualSort SortActual
        { sortActualName = testId "String"
        , sortActualSorts = []
        }

-- | Declare 'stringSort' in a Kore module.
stringSortDecl :: KoreSentence
stringSortDecl =
    hookedSortDecl
        stringSort
        [ hookAttribute "STRING.String" ]

-- -------------------------------------------------------------
-- * Modules

-- | Declare a symbol hooked to the given builtin name.
symbolDecl
    :: SymbolOrAlias Object
    -- ^ symbol
    -> Sort Object
    -- ^ result sort
    -> [Sort Object]
    -- ^ argument sorts
    -> [CommonKorePattern]
    -- ^ declaration attributes
    -> KoreSentence
symbolDecl
    SymbolOrAlias { symbolOrAliasConstructor }
    sentenceSymbolResultSort
    sentenceSymbolSorts
    (Attributes -> sentenceSymbolAttributes)
  =
    asSentence sentence
  where
    sentence :: KoreSentenceSymbol Object
    sentence =
        SentenceSymbol
            { sentenceSymbolSymbol
            , sentenceSymbolSorts
            , sentenceSymbolResultSort
            , sentenceSymbolAttributes
            }
    sentenceSymbolSymbol =
        Symbol
            { symbolConstructor = symbolOrAliasConstructor
            , symbolParams = []
            }

-- | Declare a symbol hooked to the given builtin name.
hookedSymbolDecl
    :: SymbolOrAlias Object
    -- ^ symbol
    -> Sort Object
    -- ^ result sort
    -> [Sort Object]
    -- ^ argument sorts
    -> [CommonKorePattern]
    -- ^ declaration attributes
    -> KoreSentence
hookedSymbolDecl
    SymbolOrAlias { symbolOrAliasConstructor }
    sentenceSymbolResultSort
    sentenceSymbolSorts
    (Attributes -> sentenceSymbolAttributes)
  =
    (asSentence . SentenceHookedSymbol) sentence
  where
    sentence :: KoreSentenceSymbol Object
    sentence =
        SentenceSymbol
            { sentenceSymbolSymbol
            , sentenceSymbolSorts
            , sentenceSymbolResultSort
            , sentenceSymbolAttributes
            }
    sentenceSymbolSymbol =
        Symbol
            { symbolConstructor = symbolOrAliasConstructor
            , symbolParams = []
            }

-- | Declare a symbol with no hook.
unhookedSymbolDecl
    :: SymbolOrAlias Object
    -- ^ symbol
    -> Sort Object
    -- ^ result sort
    -> [Sort Object]
    -- ^ argument sorts
    -> [CommonKorePattern]
    -- ^ declaration attributes
    -> KoreSentence
unhookedSymbolDecl
    SymbolOrAlias { symbolOrAliasConstructor }
    sentenceSymbolResultSort
    sentenceSymbolSorts
    (Attributes -> sentenceSymbolAttributes)
  =
    asSentence sentence
  where
    sentence :: KoreSentenceSymbol Object
    sentence =
        SentenceSymbol
            { sentenceSymbolSymbol
            , sentenceSymbolSorts
            , sentenceSymbolResultSort
            , sentenceSymbolAttributes
            }
    sentenceSymbolSymbol =
        Symbol
            { symbolConstructor = symbolOrAliasConstructor
            , symbolParams = []
            }

importKoreModule :: ModuleName -> KoreSentence
importKoreModule moduleName =
    asSentence sentence
  where
    sentence :: KoreSentenceImport
    sentence =
        SentenceImport
            { sentenceImportModuleName = moduleName
            , sentenceImportAttributes = Attributes []
            }

-- ** BOOL

boolModuleName :: ModuleName
boolModuleName = ModuleName "BOOL"

-- | Declare the @BOOL@ builtins.
boolModule :: KoreModule
boolModule =
    Module
        { moduleName = boolModuleName
        , moduleAttributes = Attributes []
        , moduleSentences =
            [ boolSortDecl
            , binarySymbolDecl orBoolSymbol
                [hookAttribute "BOOL.or", smthookAttribute "or"]
            , binarySymbolDecl orElseBoolSymbol
                [hookAttribute "BOOL.orElse"]
            , binarySymbolDecl andBoolSymbol
                [hookAttribute "BOOL.and", smthookAttribute "and"]
            , binarySymbolDecl andThenBoolSymbol
                [hookAttribute "BOOL.andThen"]
            , binarySymbolDecl xorBoolSymbol
                [hookAttribute "BOOL.xor", smthookAttribute "xor"]
            , binarySymbolDecl neBoolSymbol
                [hookAttribute "BOOL.ne", smthookAttribute "distinct"]
            , binarySymbolDecl eqBoolSymbol
                [hookAttribute "BOOL.eq", smthookAttribute "="]
            , binarySymbolDecl impliesBoolSymbol
                [hookAttribute "BOOL.implies", smthookAttribute "=>"]
            , hookedSymbolDecl notBoolSymbol boolSort [boolSort]
                [hookAttribute "BOOL.not", smthookAttribute "not"]
            ]
        }
  where
    binarySymbolDecl symbol attrs =
        hookedSymbolDecl symbol boolSort [boolSort, boolSort] attrs

-- ** INT

intModuleName :: ModuleName
intModuleName = ModuleName "INT"

-- | Declare the @INT@ builtins.
intModule :: KoreModule
intModule =
    Module
        { moduleName = intModuleName
        , moduleAttributes = Attributes []
        , moduleSentences =
            [ importKoreModule boolModuleName
            , intSortDecl
            -- comparison symbols
            , comparisonSymbolDecl gtIntSymbol
                [hookAttribute "INT.gt", smthookAttribute ">"]
            , comparisonSymbolDecl geIntSymbol
                [hookAttribute "INT.ge", smthookAttribute ">="]
            , comparisonSymbolDecl eqIntSymbol
                [hookAttribute "INT.eq", smthookAttribute "="]
            , comparisonSymbolDecl leIntSymbol
                [hookAttribute "INT.le", smthookAttribute "<="]
            , comparisonSymbolDecl ltIntSymbol
                [hookAttribute "INT.lt", smthookAttribute "<"]
            , comparisonSymbolDecl neIntSymbol
                [hookAttribute "INT.ne", smthookAttribute "distinct"]

            , binarySymbolDecl minIntSymbol
                [hookAttribute "INT.min", smtlibAttribute "int_min"]
            , binarySymbolDecl maxIntSymbol
                [hookAttribute "INT.max", smtlibAttribute "int_max"]
            , binarySymbolDecl addIntSymbol
                [hookAttribute "INT.add", smthookAttribute "+"]
            , binarySymbolDecl subIntSymbol
                [hookAttribute "INT.sub", smthookAttribute "-"]
            , binarySymbolDecl mulIntSymbol
                [hookAttribute "INT.mul", smthookAttribute "*"]
            , unarySymbolDecl absIntSymbol
                [ hookAttribute "INT.abs", smtlibAttribute "int_abs"
                , functionalAttribute]
            , binarySymbolDecl tdivIntSymbol
                [hookAttribute "INT.tdiv", smthookAttribute "div"]
            , binarySymbolDecl tmodIntSymbol
                [hookAttribute "INT.tmod", smthookAttribute "mod"]
            , binarySymbolDecl emodIntSymbol
                [hookAttribute "INT.emod", smthookAttribute "mod"]
            , unhookedUnarySymbolDecl dummyIntSymbol
                []
            , binarySymbolDecl andIntSymbol
                [hookAttribute "INT.and"]
            , binarySymbolDecl orIntSymbol
                [hookAttribute "INT.or"]
            , binarySymbolDecl xorIntSymbol
                [hookAttribute "INT.xor"]
            , unarySymbolDecl notIntSymbol
                [hookAttribute "INT.not"]
            , binarySymbolDecl shlIntSymbol
                [hookAttribute "INT.shl"]
            , binarySymbolDecl shrIntSymbol
                [hookAttribute "INT.shr"]
            , binarySymbolDecl powIntSymbol
                [hookAttribute "INT.pow"]
            , hookedSymbolDecl
                powmodIntSymbol
                intSort
                [intSort, intSort, intSort]
                [hookAttribute "INT.powmod"]
            , unarySymbolDecl log2IntSymbol
                [hookAttribute "INT.log2"]
            ]
        }
  where
    comparisonSymbolDecl symbol =
        hookedSymbolDecl symbol boolSort [intSort, intSort]

    unarySymbolDecl symbol =
        hookedSymbolDecl symbol intSort [intSort]

    binarySymbolDecl symbol =
        hookedSymbolDecl symbol intSort [intSort, intSort]

    unhookedUnarySymbolDecl symbol =
        unhookedSymbolDecl symbol intSort [intSort]

-- ** KEQUAL

kEqualModuleName :: ModuleName
kEqualModuleName = ModuleName "KEQUAL"

-- | Declare the @KEQUAL@ builtins.
kEqualModule :: KoreModule
kEqualModule =
    Module
        { moduleName = kEqualModuleName
        , moduleAttributes = Attributes []
        , moduleSentences =
            [ importKoreModule boolModuleName
            , hookedSymbolDecl
                keqBoolSymbol
                boolSort
                [boolSort, boolSort]
                [hookAttribute "KEQUAL.eq"]
            , hookedSymbolDecl
                kneqBoolSymbol
                boolSort
                [boolSort, boolSort]
                [hookAttribute "KEQUAL.neq"]
            , hookedSymbolDecl
                kiteKSymbol
                kSort
                [boolSort, kSort, kSort]
                [hookAttribute "KEQUAL.ite"]
            , sortDecl kSort
            , sortDecl kItemSort
            , sortDecl idSort
            , symbolDecl kseqSymbol kSort [kSort, kSort] []
            , symbolDecl dotkSymbol kSort [] []
            , injSymbolDecl
            ]
        }

injSymbolDecl :: KoreSentence
injSymbolDecl =
    asSentence decl
  where
    decl :: KoreSentenceSymbol Object
    decl =
        SentenceSymbol
            { sentenceSymbolSymbol =
                Symbol
                    { symbolConstructor =
                        let SymbolOrAlias { symbolOrAliasConstructor } =
                                injSymbol fromSort toSort
                        in symbolOrAliasConstructor
                    , symbolParams = [fromSortVariable, toSortVariable]
                    }
            , sentenceSymbolSorts = [fromSort, toSort]
            , sentenceSymbolResultSort = toSort
            , sentenceSymbolAttributes =
                Attributes
                    [ constructorAttribute
                    , injectiveAttribute
                    ]
            }
    fromSortVariable = SortVariable (testId "from")
    toSortVariable = SortVariable (testId "to")
    fromSort = SortVariableSort fromSortVariable
    toSort = SortVariableSort toSortVariable

-- ** LIST

listModuleName :: ModuleName
listModuleName = ModuleName "LIST"

-- | Declare the @LIST@ builtins.
listModule :: KoreModule
listModule =
    Module
        { moduleName = listModuleName
        , moduleAttributes = Attributes []
        , moduleSentences =
            [ importKoreModule intModuleName
            , listSortDecl
            , hookedSymbolDecl
                unitListSymbol
                listSort
                []
                [hookAttribute "LIST.unit"]
            , hookedSymbolDecl
                elementListSymbol
                listSort
                [intSort]
                [ hookAttribute "LIST.element"
                , functionalAttribute
                ]
            , hookedSymbolDecl
                concatListSymbol
                listSort
                [listSort, listSort]
                [ hookAttribute "LIST.concat"
                , functionalAttribute
                ]
            , hookedSymbolDecl
                getListSymbol
                intSort
                [listSort, intSort]
                [hookAttribute "LIST.get"]
            -- A second builtin List sort, to confuse 'asPattern'.
            , listSortDecl2
            , hookedSymbolDecl
                unitList2Symbol
                listSort2
                []
                [hookAttribute "LIST.unit"]
            , hookedSymbolDecl
                elementList2Symbol
                listSort2
                [intSort]
                [ hookAttribute "LIST.element"
                , functionalAttribute
                ]
            , hookedSymbolDecl
                concatList2Symbol
                listSort2
                [listSort2, listSort2]
                [ hookAttribute "LIST.concat"
                , functionalAttribute
                ]
            ]
        }

-- ** MAP

mapModuleName :: ModuleName
mapModuleName = ModuleName "MAP"

-- | Declare the @MAP@ builtins.
mapModule :: KoreModule
mapModule =
    Module
        { moduleName = mapModuleName
        , moduleAttributes = Attributes []
        , moduleSentences =
            [ importKoreModule boolModuleName
            , importKoreModule intModuleName
            , importKoreModule setModuleName
            , mapSortDecl
            , hookedSymbolDecl
                unitMapSymbol
                mapSort
                []
                [hookAttribute "MAP.unit"]
            , hookedSymbolDecl
                (builtinSymbol "elementMap")
                mapSort
                [intSort, intSort]
                [ hookAttribute "MAP.element"
                , functionalAttribute
                ]
            , hookedSymbolDecl
                concatMapSymbol
                mapSort
                [mapSort, mapSort]
                [ hookAttribute "MAP.concat"
                , functionalAttribute
                ]
            , hookedSymbolDecl
                lookupMapSymbol
                intSort
                [mapSort, intSort]
                [hookAttribute "MAP.lookup"]
            , hookedSymbolDecl
                updateMapSymbol
                mapSort
                [mapSort, intSort, intSort]
                [hookAttribute "MAP.update"]
            , hookedSymbolDecl
                inKeysMapSymbol
                boolSort
                [intSort, mapSort]
                [hookAttribute "MAP.in_keys"]
            , hookedSymbolDecl
                keysMapSymbol
                setSort
                [mapSort]
                [hookAttribute "MAP.keys"]
            ]
        }

-- ** PAIR

pairModuleName :: ModuleName
pairModuleName = ModuleName "PAIR"

{- | Declare the @Pair@ sort and constructors.
 -}
pairModule :: KoreModule
pairModule =
    Module
        { moduleName = pairModuleName
        , moduleAttributes = Attributes []
        , moduleSentences =
            [ pairSortDecl
            , pairSymbolDecl
            ]
        }

pairSymbolDecl :: KoreSentence
pairSymbolDecl =
    asSentence decl
  where
    decl :: KoreSentenceSymbol Object
    decl =
        SentenceSymbol
            { sentenceSymbolSymbol =
                Symbol
                    { symbolConstructor =
                        let SymbolOrAlias { symbolOrAliasConstructor } =
                                pairSymbol leftSort rightSort
                        in symbolOrAliasConstructor
                    , symbolParams = [leftSortVariable, rightSortVariable]
                    }
            , sentenceSymbolSorts = [leftSort, rightSort]
            , sentenceSymbolResultSort = rightSort
            , sentenceSymbolAttributes =
                Attributes
                    [ constructorAttribute
                    , injectiveAttribute
                    , functionalAttribute
                    ]
            }
    leftSortVariable = SortVariable (testId "left")
    rightSortVariable = SortVariable (testId "right")
    leftSort = SortVariableSort leftSortVariable
    rightSort = SortVariableSort rightSortVariable

-- ** SET

setModuleName :: ModuleName
setModuleName = ModuleName "SET"

-- | Declare the @SET@ builtins.
setModule :: KoreModule
setModule =
    Module
        { moduleName = setModuleName
        , moduleAttributes = Attributes []
        , moduleSentences =
            [ importKoreModule intModuleName
            , importKoreModule boolModuleName
            , importKoreModule listModuleName
            , setSortDecl
            , hookedSymbolDecl
                unitSetSymbol
                setSort
                []
                [hookAttribute Set.unitKey]
            , hookedSymbolDecl
                elementSetSymbol
                setSort
                [intSort]
                [ hookAttribute Set.elementKey
                , functionalAttribute
                ]
            , hookedSymbolDecl
                concatSetSymbol
                setSort
                [setSort, setSort]
                [ hookAttribute Set.concatKey
                , functionalAttribute
                ]
            , hookedSymbolDecl
                inSetSymbol
                boolSort
                [intSort, setSort]
                [hookAttribute Set.inKey]
            , hookedSymbolDecl
                differenceSetSymbol
                setSort
                [setSort, setSort]
                [hookAttribute Set.differenceKey]
            , hookedSymbolDecl
                toListSetSymbol
                listSort
                [setSort]
                [hookAttribute Set.toListKey]
            , hookedSymbolDecl
                sizeSetSymbol
                intSort
                [setSort]
                [hookAttribute Set.sizeKey]
            ]
        }

-- ** STRING

stringModuleName :: ModuleName
stringModuleName = ModuleName "STRING"

-- | Declare the @STRING@ builtins.
stringModule :: KoreModule
stringModule =
    Module
        { moduleName = stringModuleName
        , moduleAttributes = Attributes []
        , moduleSentences =
            [ importKoreModule boolModuleName
            , importKoreModule intModuleName
            , stringSortDecl
            , hookedSymbolDecl
                ltStringSymbol
                boolSort
                [stringSort, stringSort]
                [hookAttribute "STRING.lt"]
            , hookedSymbolDecl
                concatStringSymbol
                stringSort
                [stringSort, stringSort]
                [hookAttribute "STRING.concat"]
            , hookedSymbolDecl
                substrStringSymbol
                stringSort
                [stringSort, intSort, intSort]
                [hookAttribute "STRING.substr"]
            , hookedSymbolDecl
                lengthStringSymbol
                intSort
                [stringSort]
                [hookAttribute "STRING.length"]
            , hookedSymbolDecl
                chrStringSymbol
                stringSort
                [intSort]
                [hookAttribute "STRING.chr"]
            , hookedSymbolDecl
                ordStringSymbol
                intSort
                [stringSort]
                [hookAttribute "STRING.ord"]
            , hookedSymbolDecl
                findStringSymbol
                intSort
                [stringSort, stringSort, intSort]
                [hookAttribute "STRING.find"]
            , hookedSymbolDecl
                string2BaseStringSymbol
                intSort
                [stringSort, intSort]
                [hookAttribute "STRING.string2base"]
            , hookedSymbolDecl
                string2IntStringSymbol
                intSort
                [stringSort]
                [hookAttribute "STRING.string2int"]
            ]
        }

-- ** KRYPTO

kryptoModuleName :: ModuleName
kryptoModuleName = ModuleName "KRYPTO"

-- | Declare the @KRYPTO@ builtins.
kryptoModule :: KoreModule
kryptoModule =
    Module
        { moduleName = kryptoModuleName
        , moduleAttributes = Attributes []
        , moduleSentences =
            [ importKoreModule stringModuleName
            , importKoreModule intModuleName
            , importKoreModule listModuleName
            , hookedSymbolDecl
                ecdsaRecoverSymbol
                stringSort
                [stringSort, intSort, stringSort, stringSort]
                [hookAttribute "KRYPTO.ecdsaRecover"]
            , hookedSymbolDecl
                keccakSymbol
                stringSort
                [stringSort]
                [hookAttribute "KRYPTO.keccak256"]
            ]
        }

-- ** TEST

testModuleName :: ModuleName
testModuleName = ModuleName "TEST"

testModule :: KoreModule
testModule =
    Module
        { moduleName = testModuleName
        , moduleAttributes = Attributes []
        , moduleSentences =
            [ importKoreModule boolModuleName
            , importKoreModule intModuleName
            , importKoreModule kEqualModuleName
            , importKoreModule listModuleName
            , importKoreModule mapModuleName
            , importKoreModule pairModuleName
            , importKoreModule setModuleName
            , importKoreModule stringModuleName
            , importKoreModule kryptoModuleName
            ]
        }

-- -------------------------------------------------------------
-- * Definition

testDefinition :: KoreDefinition
testDefinition =
    Definition
        { definitionAttributes = Attributes []
        , definitionModules =
            [ boolModule
            , intModule
            , kEqualModule
            , listModule
            , mapModule
            , pairModule
            , setModule
            , stringModule
            , kryptoModule
            , testModule
            ]
        }
