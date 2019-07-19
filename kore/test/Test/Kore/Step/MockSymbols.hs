module Test.Kore.Step.MockSymbols where

{- Intended usage:
   * Import qualified.
   * use attributesMapping to build mock MetadataTools.
   * Use things like a, b, c, x, y, z for testing.

   RULES:
   * Everything that does not obey the default rules must be clearly
     specified in the name, e.g. 'constantNotFunctional'.
   * constant symbols are, by default, functional.
   * constant functions are called cf, cg, ch.
   * constant constructors are called a, b, c, ...
   * one-element functions are called f, g, h.
   * constructors are called "constr<n><k>" where n is the arity and k is used
     to differentiate between them (both are one-digit).
   * functional constructors are called "functionallConstr<n><k>"
   * functional symbols are called "functional<n><k>"
   * symbols without any special attribute are called "plain<n><k>"
   * variables are called x, y, z...
-}

import           Control.Applicative
import qualified Control.Lens as Lens
import qualified Data.Bifunctor as Bifunctor
import qualified Data.Default as Default
import qualified Data.Either as Either
import           Data.Function
import           Data.Generics.Product
import qualified Data.Map.Strict as Map
import qualified Data.Sequence as Seq
import           Data.Text
                 ( Text )
import qualified GHC.Stack as GHC

import           Data.Sup
import           Kore.Attribute.Hook
                 ( Hook (..) )
import qualified Kore.Attribute.Sort as Attribute
import qualified Kore.Attribute.Sort.Concat as Attribute
import qualified Kore.Attribute.Sort.Element as Attribute
import qualified Kore.Attribute.Sort.Unit as Attribute
import qualified Kore.Attribute.Symbol as Attribute
import qualified Kore.Builtin.Bool as Builtin.Bool
import qualified Kore.Builtin.Int as Builtin.Int
import qualified Kore.Domain.Builtin as Domain
import           Kore.IndexedModule.MetadataTools
                 ( SmtMetadataTools )
import           Kore.Internal.ApplicationSorts
                 ( ApplicationSorts )
import           Kore.Internal.Symbol
import           Kore.Internal.TermLike
                 ( TermLike )
import qualified Kore.Internal.TermLike as Internal
import           Kore.Sort
import           Kore.Step.Simplification.Data hiding
                 ( termLikeSimplifier )
import qualified Kore.Step.Simplification.Predicate as Simplifier.Predicate
import qualified Kore.Step.Simplification.Simplifier as Simplifier
import qualified Kore.Step.SMT.AST as SMT
import qualified Kore.Step.SMT.Representation.Resolve as SMT
                 ( resolve )
import           Kore.Syntax.Application
import           Kore.Syntax.SetVariable
import           Kore.Syntax.Variable
import           Kore.Unparser
import qualified SMT.AST as SMT
import qualified SMT.SimpleSMT as SMT

import           Test.Kore
                 ( testId )
import qualified Test.Kore.IndexedModule.MockMetadataTools as Mock

aId :: Id
aId = testId "a"
aSort0Id :: Id
aSort0Id = testId "aSort0"
aSort1Id :: Id
aSort1Id = testId "aSort1"
aSubsortId :: Id
aSubsortId = testId "aSubsort"
aSubOthersortId :: Id
aSubOthersortId = testId "aSubOthersort"
aSubSubsortId :: Id
aSubSubsortId = testId "aSubSubsort"
aTopSortId :: Id
aTopSortId = testId "aTopSort"
aOtherSortId :: Id
aOtherSortId = testId "aOtherSort"
bId :: Id
bId = testId "b"
bSort0Id :: Id
bSort0Id = testId "bSort0"
cId :: Id
cId = testId "c"
dId :: Id
dId = testId "d"
eId :: Id
eId = testId "e"
fId :: Id
fId = testId "f"
gId :: Id
gId = testId "g"
hId :: Id
hId = testId "h"
cfId :: Id
cfId = testId "cf"
cfSort0Id :: Id
cfSort0Id = testId "cfSort0"
cfSort1Id :: Id
cfSort1Id = testId "cfSort1"
cgId :: Id
cgId = testId "cg"
cgSort0Id :: Id
cgSort0Id = testId "cgSort0"
chId :: Id
chId = testId "ch"
fSetId :: Id
fSetId = testId "fSet"
plain00Id :: Id
plain00Id = testId "plain00"
plain00Sort0Id :: Id
plain00Sort0Id = testId "plain00Sort0"
plain00SubsortId :: Id
plain00SubsortId = testId "plain00Subsort"
plain00SubSubsortId :: Id
plain00SubSubsortId = testId "plain00SubSubsort"
plain10Id :: Id
plain10Id = testId "plain10"
plain11Id :: Id
plain11Id = testId "plain11"
plain20Id :: Id
plain20Id = testId "plain20"
constr00Id :: Id
constr00Id = testId "constr00"
constr10Id :: Id
constr10Id = testId "constr10"
constr11Id :: Id
constr11Id = testId "constr11"
constr20Id :: Id
constr20Id = testId "constr20"
function20MapTestId :: Id
function20MapTestId = testId "function20MapTest"
functional00Id :: Id
functional00Id = testId "functional00"
functional01Id :: Id
functional01Id = testId "functional01"
functional10Id :: Id
functional10Id = testId "functional10"
functional11Id :: Id
functional11Id = testId "functional11"
functional20Id :: Id
functional20Id = testId "functional20"
functional00SubSubSortId :: Id
functional00SubSubSortId = testId "functional00SubSubSort"
functionalInjective00Id :: Id
functionalInjective00Id = testId "functionalInjective00"
functionalConstr10Id :: Id
functionalConstr10Id = testId "functionalConstr10"
functionalConstr11Id :: Id
functionalConstr11Id = testId "functionalConstr11"
functionalConstr12Id :: Id
functionalConstr12Id = testId "functionalConstr12"
functionalConstr20Id :: Id
functionalConstr20Id = testId "functionalConstr20"
functionalConstr21Id :: Id
functionalConstr21Id = testId "functionalConstr21"
functionalConstr30Id :: Id
functionalConstr30Id = testId "functionalConstr30"
functionalTopConstr20Id :: Id
functionalTopConstr20Id = testId "functionalTopConstr20"
functionalTopConstr21Id :: Id
functionalTopConstr21Id = testId "functionalTopConstr21"
injective10Id :: Id
injective10Id = testId "injective10"
injective11Id :: Id
injective11Id = testId "injective11"
sortInjectionId :: Id
sortInjectionId = testId "sortInjection"
unitMapId :: Id
unitMapId = testId "unitMap"
elementMapId :: Id
elementMapId = testId "elementMap"
concatMapId :: Id
concatMapId = testId "concatMap"
lessIntId :: Id
lessIntId = testId "lessIntId"
greaterEqIntId :: Id
greaterEqIntId = testId "greaterEqIntId"
concatListId :: Id
concatListId = testId "concatList"
elementListId :: Id
elementListId = testId "elementList"
unitListId :: Id
unitListId = testId "unitList"
concatSetId :: Id
concatSetId = testId "concatSet"
elementSetId :: Id
elementSetId = testId "elementSet"
unitSetId :: Id
unitSetId = testId "unitSet"
sigmaId :: Id
sigmaId = testId "sigma"
anywhereId :: Id
anywhereId = testId "anywhere"

symbol :: Id -> [Sort] -> Sort -> Symbol
symbol name operands result =
    Symbol
        { symbolConstructor = name
        , symbolParams = []
        , symbolAttributes = Default.def
        , symbolSorts = applicationSorts operands result
        }

aSymbol :: Symbol
aSymbol = symbol aId [] testSort & functional & constructor

aSort0Symbol :: Symbol
aSort0Symbol = symbol aSort0Id [] testSort0 & functional & constructor

aSort1Symbol :: Symbol
aSort1Symbol = symbol aSort1Id [] testSort1 & functional & constructor

aSubsortSymbol :: Symbol
aSubsortSymbol = symbol aSubsortId [] subSort & functional & constructor

aSubOthersortSymbol :: Symbol
aSubOthersortSymbol =
    symbol aSubOthersortId [] subOthersort & functional & constructor

aSubSubsortSymbol :: Symbol
aSubSubsortSymbol =
    symbol aSubSubsortId [] subSubsort & functional & constructor

aTopSortSymbol :: Symbol
aTopSortSymbol = symbol aTopSortId [] topSort & functional & constructor

aOtherSortSymbol :: Symbol
aOtherSortSymbol = symbol aOtherSortId [] otherSort & functional & constructor

bSymbol :: Symbol
bSymbol = symbol bId [] testSort & functional & constructor

bSort0Symbol :: Symbol
bSort0Symbol = symbol bSort0Id [] testSort0 & functional & constructor

cSymbol :: Symbol
cSymbol = symbol cId [] testSort & functional & constructor

dSymbol :: Symbol
dSymbol = symbol dId [] testSort & functional & constructor

eSymbol :: Symbol
eSymbol = symbol eId [] testSort & functional & constructor

fSymbol :: Symbol
fSymbol = symbol fId [testSort] testSort & function

gSymbol :: Symbol
gSymbol = symbol gId [testSort] testSort & function

hSymbol :: Symbol
hSymbol = symbol hId [testSort] testSort & function

cfSymbol :: Symbol
cfSymbol = symbol cfId [] testSort & function

cfSort0Symbol :: Symbol
cfSort0Symbol = symbol cfSort0Id [] testSort0 & function

cfSort1Symbol :: Symbol
cfSort1Symbol = symbol cfSort1Id [] testSort1 & function

cgSymbol :: Symbol
cgSymbol = symbol cgId [] testSort & function

cgSort0Symbol :: Symbol
cgSort0Symbol = symbol cgSort0Id [] testSort0 & function

chSymbol :: Symbol
chSymbol = symbol chId [] testSort & function

fSetSymbol :: Symbol
fSetSymbol = symbol fSetId [setSort] setSort & function

plain00Symbol :: Symbol
plain00Symbol = symbol plain00Id [] testSort

plain00Sort0Symbol :: Symbol
plain00Sort0Symbol = symbol plain00Sort0Id [] testSort0

plain00SubsortSymbol :: Symbol
plain00SubsortSymbol = symbol plain00SubsortId [] subSort

plain00SubSubsortSymbol :: Symbol
plain00SubSubsortSymbol = symbol plain00SubSubsortId [] subSubsort

plain10Symbol :: Symbol
plain10Symbol = symbol plain10Id [testSort] testSort

plain11Symbol :: Symbol
plain11Symbol = symbol plain11Id [testSort] testSort

plain20Symbol :: Symbol
plain20Symbol = symbol plain20Id [testSort, testSort] testSort

constr00Symbol :: Symbol
constr00Symbol = symbol constr00Id [] testSort & constructor

constr10Symbol :: Symbol
constr10Symbol = symbol constr10Id [testSort] testSort & constructor

constr11Symbol :: Symbol
constr11Symbol = symbol constr11Id [testSort] testSort & constructor

constr20Symbol :: Symbol
constr20Symbol = symbol constr20Id [testSort, testSort] testSort & constructor

function20MapTestSymbol :: Symbol
function20MapTestSymbol =
    symbol function20MapTestId [mapSort, testSort] testSort & function

functional00Symbol :: Symbol
functional00Symbol = symbol functional00Id [] testSort & functional

functional01Symbol :: Symbol
functional01Symbol = symbol functional01Id [] testSort & functional

functional10Symbol :: Symbol
functional10Symbol = symbol functional10Id [testSort] testSort & functional

functional11Symbol :: Symbol
functional11Symbol = symbol functional11Id [testSort] testSort & functional

functional20Symbol :: Symbol
functional20Symbol =
    symbol functional20Id [testSort, testSort] testSort & functional

functional00SubSubSortSymbol :: Symbol
functional00SubSubSortSymbol =
    symbol functional00SubSubSortId [] subSubsort & functional

functionalInjective00Symbol :: Symbol
functionalInjective00Symbol =
    symbol functionalInjective00Id [] testSort & functional & injective

functionalConstr10Symbol :: Symbol
functionalConstr10Symbol =
    symbol functionalConstr10Id [testSort] testSort & functional & constructor

functionalConstr11Symbol :: Symbol
functionalConstr11Symbol =
    symbol functionalConstr11Id [testSort] testSort & functional & constructor

functionalConstr12Symbol :: Symbol
functionalConstr12Symbol =
    symbol functionalConstr12Id [testSort] testSort & functional & constructor

functionalConstr20Symbol :: Symbol
functionalConstr20Symbol =
    symbol functionalConstr20Id [testSort, testSort] testSort
    & functional & constructor

functionalConstr21Symbol :: Symbol
functionalConstr21Symbol =
    symbol functionalConstr21Id [testSort, testSort] testSort
    & functional & constructor

functionalConstr30Symbol :: Symbol
functionalConstr30Symbol =
    symbol functionalConstr30Id [testSort, testSort, testSort] testSort
    & functional & constructor

functionalTopConstr20Symbol :: Symbol
functionalTopConstr20Symbol =
    symbol functionalTopConstr20Id [topSort, testSort] testSort
    & functional & constructor

functionalTopConstr21Symbol :: Symbol
functionalTopConstr21Symbol =
    symbol functionalTopConstr21Id [testSort, topSort] testSort
    & functional & constructor

injective10Symbol :: Symbol
injective10Symbol = symbol injective10Id [testSort] testSort & injective

injective11Symbol :: Symbol
injective11Symbol = symbol injective11Id [testSort] testSort & injective

sortInjectionSymbol :: Sort -> Sort -> Symbol
sortInjectionSymbol fromSort toSort = Symbol
    { symbolConstructor = sortInjectionId
    , symbolParams      = [fromSort, toSort]
    , symbolAttributes  = Mock.sortInjectionAttributes
    , symbolSorts = applicationSorts [fromSort] toSort
    }

sortInjection10Symbol :: Symbol
sortInjection10Symbol = sortInjectionSymbol testSort0 testSort

sortInjection11Symbol :: Symbol
sortInjection11Symbol = sortInjectionSymbol testSort1 testSort

sortInjection0ToTopSymbol :: Symbol
sortInjection0ToTopSymbol = sortInjectionSymbol testSort0 topSort

sortInjectionSubToTopSymbol :: Symbol
sortInjectionSubToTopSymbol = sortInjectionSymbol subSort topSort

sortInjectionSubSubToTopSymbol :: Symbol
sortInjectionSubSubToTopSymbol = sortInjectionSymbol subSubsort topSort

sortInjectionSubSubToSubSymbol :: Symbol
sortInjectionSubSubToSubSymbol = sortInjectionSymbol subSubsort subSort

sortInjectionSubSubToOtherSymbol :: Symbol
sortInjectionSubSubToOtherSymbol = sortInjectionSymbol subSubsort otherSort

sortInjectionSubOtherToOtherSymbol :: Symbol
sortInjectionSubOtherToOtherSymbol = sortInjectionSymbol subOthersort otherSort

sortInjectionOtherToTopSymbol :: Symbol
sortInjectionOtherToTopSymbol = sortInjectionSymbol otherSort topSort

unitMapSymbol :: Symbol
unitMapSymbol =
    symbol unitMapId [] mapSort
    & functional & hook "MAP.unit"

elementMapSymbol :: Symbol
elementMapSymbol =
    symbol elementMapId [testSort, testSort] mapSort
    & functional & hook "MAP.element"

concatMapSymbol :: Symbol
concatMapSymbol =
    symbol concatMapId [mapSort, mapSort] mapSort
    & functional & hook "MAP.concat"

lessIntSymbol :: Symbol
lessIntSymbol =
    symbol lessIntId [intSort, intSort] boolSort
    & functional & hook "INT.lt" & smthook "<"

greaterEqIntSymbol :: Symbol
greaterEqIntSymbol =
    symbol greaterEqIntId [intSort, intSort] boolSort
    & functional & hook "INT.ge" & smthook ">="

concatListSymbol :: Symbol
concatListSymbol =
    symbol concatListId [listSort, listSort] listSort
    & functional & hook "LIST.concat"

elementListSymbol :: Symbol
elementListSymbol =
    symbol elementListId [testSort] listSort
    & functional & hook "LIST.element"

unitListSymbol :: Symbol
unitListSymbol = symbol unitListId [] listSort & functional & hook "LIST.unit"

concatSetSymbol :: Symbol
concatSetSymbol =
    symbol concatSetId [setSort, setSort] setSort
    & functional & hook "SET.concat"

elementSetSymbol :: Symbol
elementSetSymbol =
    symbol elementSetId [testSort] setSort & functional & hook "SET.element"

unitSetSymbol :: Symbol
unitSetSymbol =
    symbol unitSetId [] setSort & functional & hook "SET.unit"

sigmaSymbol :: Symbol
sigmaSymbol =
    symbol sigmaId [testSort, testSort] testSort
    & functional & constructor

anywhereSymbol :: Symbol
anywhereSymbol =
    symbol anywhereId [] testSort
    & functional
    & Lens.set
        (typed @Attribute.Symbol . typed @Attribute.Anywhere)
        (Attribute.Anywhere True)

var_x_1 :: Variable
var_x_1 = Variable (testId "x") (Just (Element 1)) testSort
var_y_1 :: Variable
var_y_1 = Variable (testId "y") (Just (Element 1)) testSort
var_z_1 :: Variable
var_z_1 = Variable (testId "z") (Just (Element 1)) testSort
x :: Variable
x = Variable (testId "x") mempty testSort
setX :: SetVariable Variable
setX = SetVariable x
x0 :: Variable
x0 = Variable (testId "x") mempty testSort0
y :: Variable
y = Variable (testId "y") mempty testSort
setY :: SetVariable Variable
setY = SetVariable y
z :: Variable
z = Variable (testId "z") mempty testSort
m :: Variable
m = Variable (testId "m") mempty mapSort
xSet :: Variable
xSet = Variable (testId "xSet") mempty setSort
ySet :: Variable
ySet = Variable (testId "ySet") mempty setSort
xInt :: Variable
xInt = Variable (testId "xInt") mempty intSort
yInt :: Variable
yInt = Variable (testId "yInt") mempty intSort
xBool :: Variable
xBool = Variable (testId "xBool") mempty boolSort
xString :: Variable
xString = Variable (testId "xString") mempty stringSort
xList :: Variable
xList = Variable (testId "xList") mempty listSort
xMap :: Variable
xMap = Variable (testId "xMap") mempty mapSort
xSubSort :: Variable
xSubSort = Variable (testId "xSubSort") mempty subSort
xSubSubSort :: Variable
xSubSubSort = Variable (testId "xSubSubSort") mempty subSubsort
xTopSort :: Variable
xTopSort = Variable (testId "xTopSort") mempty topSort

a :: (Ord variable, SortedVariable variable, Unparse variable) => TermLike variable
a = Internal.mkApplySymbol aSymbol []

aConcrete :: TermLike Concrete
Just aConcrete = Internal.asConcrete (a :: TermLike Variable)

aSort0 :: (Ord variable, SortedVariable variable, Unparse variable) => TermLike variable
aSort0 = Internal.mkApplySymbol aSort0Symbol []

aSort1 :: (Ord variable, SortedVariable variable, Unparse variable) => TermLike variable
aSort1 = Internal.mkApplySymbol aSort1Symbol []

aSubsort :: (Ord variable, SortedVariable variable, Unparse variable) => TermLike variable
aSubsort = Internal.mkApplySymbol aSubsortSymbol []

aSubOthersort
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => TermLike variable
aSubOthersort = Internal.mkApplySymbol aSubOthersortSymbol []

aSubSubsort
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => TermLike variable
aSubSubsort = Internal.mkApplySymbol aSubSubsortSymbol []

aTopSort :: (Ord variable, SortedVariable variable, Unparse variable) => TermLike variable
aTopSort = Internal.mkApplySymbol aTopSortSymbol []

aOtherSort :: (Ord variable, SortedVariable variable, Unparse variable) => TermLike variable
aOtherSort = Internal.mkApplySymbol aOtherSortSymbol []

b :: (Ord variable, SortedVariable variable, Unparse variable) => TermLike variable
b = Internal.mkApplySymbol bSymbol []

bConcrete :: TermLike Concrete
Just bConcrete = Internal.asConcrete (b :: TermLike Variable)

bSort0 :: (Ord variable, SortedVariable variable, Unparse variable) => TermLike variable
bSort0 = Internal.mkApplySymbol bSort0Symbol []

c :: (Ord variable, SortedVariable variable, Unparse variable) => TermLike variable
c = Internal.mkApplySymbol cSymbol []

d :: (Ord variable, SortedVariable variable, Unparse variable) => TermLike variable
d = Internal.mkApplySymbol dSymbol []

e :: (Ord variable, SortedVariable variable, Unparse variable) => TermLike variable
e = Internal.mkApplySymbol eSymbol []

f, g, h
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => TermLike variable
    -> TermLike variable
f arg = Internal.mkApplySymbol fSymbol [arg]
g arg = Internal.mkApplySymbol gSymbol [arg]
h arg = Internal.mkApplySymbol hSymbol [arg]

cf :: (Ord variable, SortedVariable variable, Unparse variable) => TermLike variable
cf = Internal.mkApplySymbol cfSymbol []

cfSort0 :: (Ord variable, SortedVariable variable, Unparse variable) => TermLike variable
cfSort0 = Internal.mkApplySymbol cfSort0Symbol []

cfSort1 :: (Ord variable, SortedVariable variable, Unparse variable) => TermLike variable
cfSort1 = Internal.mkApplySymbol cfSort1Symbol []

cg :: (Ord variable, SortedVariable variable, Unparse variable) => TermLike variable
cg = Internal.mkApplySymbol cgSymbol []

cgSort0 :: (Ord variable, SortedVariable variable, Unparse variable) => TermLike variable
cgSort0 = Internal.mkApplySymbol cgSort0Symbol []

ch :: (Ord variable, SortedVariable variable, Unparse variable) => TermLike variable
ch = Internal.mkApplySymbol chSymbol []

fSet
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => TermLike variable
    -> TermLike variable
fSet arg = Internal.mkApplySymbol fSetSymbol [arg]

plain00 :: (Ord variable, SortedVariable variable, Unparse variable) => TermLike variable
plain00 = Internal.mkApplySymbol plain00Symbol []

plain00Sort0 :: (Ord variable, SortedVariable variable, Unparse variable) => TermLike variable
plain00Sort0 = Internal.mkApplySymbol plain00Sort0Symbol []

plain00Subsort :: (Ord variable, SortedVariable variable, Unparse variable) => TermLike variable
plain00Subsort = Internal.mkApplySymbol plain00SubsortSymbol []

plain00SubSubsort :: (Ord variable, SortedVariable variable, Unparse variable) => TermLike variable
plain00SubSubsort = Internal.mkApplySymbol plain00SubSubsortSymbol []

plain10, plain11
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => TermLike variable
    -> TermLike variable
plain10 arg = Internal.mkApplySymbol plain10Symbol [arg]
plain11 arg = Internal.mkApplySymbol plain11Symbol [arg]

plain20
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => TermLike variable
    -> TermLike variable
    -> TermLike variable
plain20 arg1 arg2 = Internal.mkApplySymbol plain20Symbol [arg1, arg2]

constr00
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => TermLike variable
constr00 = Internal.mkApplySymbol constr00Symbol []

constr10, constr11
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => TermLike variable
    -> TermLike variable
constr10 arg = Internal.mkApplySymbol constr10Symbol [arg]
constr11 arg = Internal.mkApplySymbol constr11Symbol [arg]

constr20
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => TermLike variable
    -> TermLike variable
    -> TermLike variable
constr20 arg1 arg2 = Internal.mkApplySymbol constr20Symbol [arg1, arg2]

function20MapTest
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => TermLike variable
    -> TermLike variable
    -> TermLike variable
function20MapTest arg1 arg2 =
    Internal.mkApplySymbol function20MapTestSymbol [arg1, arg2]

functional00
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => TermLike variable
functional00 = Internal.mkApplySymbol functional00Symbol []

functional01
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => TermLike variable
functional01 = Internal.mkApplySymbol functional01Symbol []

functional10
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => TermLike variable
    -> TermLike variable
functional10 arg = Internal.mkApplySymbol functional10Symbol [arg]

functional11
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => TermLike variable
    -> TermLike variable
functional11 arg = Internal.mkApplySymbol functional11Symbol [arg]

functional20
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => TermLike variable
    -> TermLike variable
    -> TermLike variable
functional20 arg1 arg2 = Internal.mkApplySymbol functional20Symbol [arg1, arg2]

functional00SubSubSort
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => TermLike variable
functional00SubSubSort =
    Internal.mkApplySymbol functional00SubSubSortSymbol []

functionalInjective00
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => TermLike variable
functionalInjective00 =
    Internal.mkApplySymbol functionalInjective00Symbol []

functionalConstr10
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => TermLike variable
    -> TermLike variable
functionalConstr10 arg =
    Internal.mkApplySymbol functionalConstr10Symbol [arg]

functionalConstr11
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => TermLike variable
    -> TermLike variable
functionalConstr11 arg = Internal.mkApplySymbol functionalConstr11Symbol [arg]

functionalConstr12
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => TermLike variable
    -> TermLike variable
functionalConstr12 arg = Internal.mkApplySymbol functionalConstr12Symbol [arg]

functionalConstr20
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => TermLike variable
    -> TermLike variable
    -> TermLike variable
functionalConstr20 arg1 arg2 =
    Internal.mkApplySymbol functionalConstr20Symbol [arg1, arg2]

functionalConstr21
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => TermLike variable
    -> TermLike variable
    -> TermLike variable
functionalConstr21 arg1 arg2 =
    Internal.mkApplySymbol functionalConstr21Symbol [arg1, arg2]

functionalConstr30
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => TermLike variable
    -> TermLike variable
    -> TermLike variable
    -> TermLike variable
functionalConstr30 arg1 arg2 arg3 =
    Internal.mkApplySymbol functionalConstr30Symbol [arg1, arg2, arg3]

functionalTopConstr20
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => TermLike variable
    -> TermLike variable
    -> TermLike variable
functionalTopConstr20 arg1 arg2 =
    Internal.mkApplySymbol functionalTopConstr20Symbol [arg1, arg2]

functionalTopConstr21
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => TermLike variable
    -> TermLike variable
    -> TermLike variable
functionalTopConstr21 arg1 arg2 =
    Internal.mkApplySymbol functionalTopConstr21Symbol [arg1, arg2]

injective10
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => TermLike variable
    -> TermLike variable
injective10 arg = Internal.mkApplySymbol injective10Symbol [arg]

injective11
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => TermLike variable
    -> TermLike variable
injective11 arg = Internal.mkApplySymbol injective11Symbol [arg]

sortInjection
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => Sort
    -> TermLike variable
    -> TermLike variable
sortInjection toSort termLike =
    Internal.mkApplySymbol (sortInjectionSymbol fromSort toSort) [termLike]
  where
    fromSort = Internal.termLikeSort termLike

sortInjection10
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => TermLike variable
    -> TermLike variable
sortInjection10 arg = Internal.mkApplySymbol sortInjection10Symbol [arg]

sortInjection11
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => TermLike variable
    -> TermLike variable
sortInjection11 arg = Internal.mkApplySymbol sortInjection11Symbol [arg]

sortInjection0ToTop
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => TermLike variable
    -> TermLike variable
sortInjection0ToTop arg =
    Internal.mkApplySymbol sortInjection0ToTopSymbol [arg]

sortInjectionSubToTop
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => TermLike variable
    -> TermLike variable
sortInjectionSubToTop arg =
    Internal.mkApplySymbol sortInjectionSubToTopSymbol [arg]

sortInjectionSubSubToTop
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => TermLike variable
    -> TermLike variable
sortInjectionSubSubToTop arg =
    Internal.mkApplySymbol sortInjectionSubSubToTopSymbol [arg]

sortInjectionSubSubToSub
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => TermLike variable
    -> TermLike variable
sortInjectionSubSubToSub arg =
    Internal.mkApplySymbol sortInjectionSubSubToSubSymbol [arg]

sortInjectionSubSubToOther
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => TermLike variable
    -> TermLike variable
sortInjectionSubSubToOther arg =
    Internal.mkApplySymbol sortInjectionSubSubToOtherSymbol [arg]

sortInjectionSubOtherToOther
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => TermLike variable
    -> TermLike variable
sortInjectionSubOtherToOther arg =
    Internal.mkApplySymbol sortInjectionSubOtherToOtherSymbol [arg]

sortInjectionOtherToTop
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => TermLike variable
    -> TermLike variable
sortInjectionOtherToTop arg =
    Internal.mkApplySymbol sortInjectionOtherToTopSymbol [arg]

unitMap :: (Ord variable, SortedVariable variable, Unparse variable) => TermLike variable
unitMap = Internal.mkApplySymbol unitMapSymbol []

elementMap
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => TermLike variable
    -> TermLike variable
    -> TermLike variable
elementMap m1 m2 = Internal.mkApplySymbol elementMapSymbol [m1, m2]

concatMap
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => TermLike variable
    -> TermLike variable
    -> TermLike variable
concatMap m1 m2 = Internal.mkApplySymbol concatMapSymbol [m1, m2]

unitSet
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => TermLike variable
unitSet = Internal.mkApplySymbol unitSetSymbol []

elementSet
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => TermLike variable
    -> TermLike variable
elementSet s1 = Internal.mkApplySymbol elementSetSymbol [s1]

concatSet
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => TermLike variable
    -> TermLike variable
    -> TermLike variable
concatSet s1 s2 = Internal.mkApplySymbol concatSetSymbol [s1, s2]

lessInt
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => TermLike variable
    -> TermLike variable
    -> TermLike variable
lessInt i1 i2 = Internal.mkApplySymbol lessIntSymbol [i1, i2]

greaterEqInt
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => TermLike variable
    -> TermLike variable
    -> TermLike variable
greaterEqInt i1 i2 = Internal.mkApplySymbol greaterEqIntSymbol [i1, i2]

concatList
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => TermLike variable
    -> TermLike variable
    -> TermLike variable
concatList l1 l2 = Internal.mkApplySymbol concatListSymbol [l1, l2]

sigma
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => TermLike variable
    -> TermLike variable
    -> TermLike variable
sigma child1 child2 = Internal.mkApplySymbol sigmaSymbol [child1, child2]

anywhere :: (Ord variable, SortedVariable variable, Unparse variable) => TermLike variable
anywhere = Internal.mkApplySymbol anywhereSymbol []

attributesMapping :: [(SymbolOrAlias, Attribute.Symbol)]
attributesMapping =
    map (liftA2 (,) toSymbolOrAlias symbolAttributes) symbols

symbols :: [Symbol]
symbols =
    [ aSymbol
    , aSort0Symbol
    , aSort1Symbol
    , aSubsortSymbol
    , aSubOthersortSymbol
    , aSubSubsortSymbol
    , aTopSortSymbol
    , aOtherSortSymbol
    , bSymbol
    , bSort0Symbol
    , cSymbol
    , dSymbol
    , eSymbol
    , fSymbol
    , gSymbol
    , hSymbol
    , cfSymbol
    , cfSort0Symbol
    , cfSort1Symbol
    , cgSymbol
    , cgSort0Symbol
    , chSymbol
    , fSetSymbol
    , plain00Symbol
    , plain00Sort0Symbol
    , plain00SubsortSymbol
    , plain00SubSubsortSymbol
    , plain10Symbol
    , plain11Symbol
    , plain20Symbol
    , constr00Symbol
    , constr10Symbol
    , constr11Symbol
    , constr20Symbol
    , function20MapTestSymbol
    , functional00Symbol
    , functional01Symbol
    , functional10Symbol
    , functional11Symbol
    , functional20Symbol
    , functional00SubSubSortSymbol
    , functionalInjective00Symbol
    , functionalConstr10Symbol
    , functionalConstr11Symbol
    , functionalConstr12Symbol
    , functionalConstr20Symbol
    , functionalConstr21Symbol
    , functionalConstr30Symbol
    , functionalTopConstr20Symbol
    , functionalTopConstr21Symbol
    , injective10Symbol
    , injective11Symbol
    , sortInjection10Symbol
    , sortInjection11Symbol
    , sortInjection0ToTopSymbol
    , sortInjectionSubToTopSymbol
    , sortInjectionSubSubToTopSymbol
    , sortInjectionSubSubToSubSymbol
    , sortInjectionSubSubToOtherSymbol
    , sortInjectionSubOtherToOtherSymbol
    , sortInjectionOtherToTopSymbol
    , unitMapSymbol
    , elementMapSymbol
    , concatMapSymbol
    , concatListSymbol
    , elementListSymbol
    , unitListSymbol
    , concatSetSymbol
    , elementSetSymbol
    , unitSetSymbol
    , lessIntSymbol
    , greaterEqIntSymbol
    , sigmaSymbol
    , anywhereSymbol
    ]

sortAttributesMapping :: [(Sort, Attribute.Sort)]
sortAttributesMapping =
    [   ( testSort
        , Default.def
        )
    ,   ( testSort0
        , Default.def
        )
    ,   ( testSort1
        , Default.def
        )
    ,   ( topSort
        , Default.def
        )
    ,   ( subSort
        , Default.def
        )
    ,   ( subOthersort
        , Default.def
        )
    ,   ( subSubsort
        , Default.def
        )
    ,   ( otherSort
        , Default.def
        )
    ,   ( mapSort
        , Default.def
            { Attribute.hook = Hook (Just "MAP.Map")
            , Attribute.unit =
                Attribute.Unit (Just $ toSymbolOrAlias unitMapSymbol)
            , Attribute.element =
                Attribute.Element (Just $ toSymbolOrAlias elementMapSymbol)
            , Attribute.concat =
                Attribute.Concat (Just $ toSymbolOrAlias concatMapSymbol)
            }
        )
    ,   ( listSort
        , Default.def
            { Attribute.hook = Hook (Just "LIST.List")
            , Attribute.unit =
                Attribute.Unit (Just $ toSymbolOrAlias unitListSymbol)
            , Attribute.element =
                Attribute.Element (Just $ toSymbolOrAlias elementListSymbol)
            , Attribute.concat =
                Attribute.Concat (Just $ toSymbolOrAlias concatListSymbol)
            }
        )
    ,   ( setSort
        , Default.def
            { Attribute.hook = Hook (Just "SET.Set")
            , Attribute.unit =
                Attribute.Unit (Just $ toSymbolOrAlias unitSetSymbol)
            , Attribute.element =
                Attribute.Element (Just $ toSymbolOrAlias elementSetSymbol)
            , Attribute.concat =
                Attribute.Concat (Just $ toSymbolOrAlias concatSetSymbol)
            }
        )
    ,   ( intSort
        , Default.def { Attribute.hook = Hook (Just "INT.Int") }
        )
    ,   ( boolSort
        , Default.def { Attribute.hook = Hook (Just "BOOL.Bool") }
        )

    -- Also add attributes for the implicitly defined sorts.
    ,   ( charMetaSort
        , Default.def
        )
    ,   ( stringMetaSort
        , Default.def { Attribute.hook = Hook (Just "STRING.String") }
        )
    ]

headSortsMapping :: [(SymbolOrAlias, ApplicationSorts)]
headSortsMapping =
    map ((,) <$> toSymbolOrAlias <*> symbolSorts) symbols

zeroarySmtSort :: Id -> SMT.UnresolvedSort
zeroarySmtSort sortId =
    SMT.Sort
        { smtFromSortArgs = const (const (Just (SMT.Atom encodedId)))
        , declaration = SMT.SortDeclarationSort SMT.SortDeclaration
            { name = SMT.encodable sortId
            , arity = 0
            }
        }
  where
    encodedId = SMT.encode (SMT.encodable sortId)

builtinZeroarySmtSort :: SMT.SExpr -> SMT.UnresolvedSort
builtinZeroarySmtSort sExpr =
    SMT.Sort
        { smtFromSortArgs = const (const (Just sExpr))
        , declaration =
            SMT.SortDeclaredIndirectly
                (SMT.AlreadyEncoded (SMT.nameFromSExpr sExpr))
        }

smtConstructor :: Id -> [Sort] -> Sort -> SMT.UnresolvedSymbol
smtConstructor symbolId argumentSorts resultSort =
    SMT.Symbol
        { smtFromSortArgs = const (const (Just (SMT.Atom encodedId)))
        , declaration =
            SMT.SymbolDeclaredIndirectly SMT.IndirectSymbolDeclaration
                { name = encodableId
                , sorts = map SMT.SortReference (resultSort : argumentSorts)
                }
        }
  where
    encodableId = SMT.encodable symbolId
    encodedId = SMT.encode encodableId

smtBuiltinSymbol
    :: Text -> [Sort] -> Sort -> SMT.UnresolvedSymbol
smtBuiltinSymbol builtin argumentSorts resultSort =
    SMT.Symbol
        { smtFromSortArgs = const (const (Just (SMT.Atom builtin)))
        , declaration =
            SMT.SymbolDeclaredIndirectly SMT.IndirectSymbolDeclaration
                { name = SMT.AlreadyEncoded builtin
                , sorts = map SMT.SortReference (resultSort : argumentSorts)
                }
        }

emptySmtDeclarations :: SMT.SmtDeclarations
emptySmtDeclarations =
    SMT.Declarations
        { sorts = Map.empty
        , symbols = Map.empty
        }

smtDeclarations :: SMT.SmtDeclarations
smtDeclarations = SMT.resolve smtUnresolvedDeclarations

smtUnresolvedDeclarations :: SMT.UnresolvedDeclarations
smtUnresolvedDeclarations = SMT.Declarations
    { sorts = Map.fromList
        [ (testSort0Id, zeroarySmtSort testSort0Id)
        , (testSort1Id, zeroarySmtSort testSort1Id)
        , (topSortId, zeroarySmtSort topSortId)
        , (topSortId, zeroarySmtSort subSortId)
        , (topSortId, zeroarySmtSort subSubsortId)
        , (topSortId, zeroarySmtSort otherSortId)
        -- TODO(virgil): testSort has constructors, it should have a
        -- constructor-based definition. The same for others.
        , (testSortId, zeroarySmtSort testSortId)
        , (intSortId, builtinZeroarySmtSort SMT.tInt)
        , (boolSortId, builtinZeroarySmtSort SMT.tBool)
        ]
    , symbols = Map.fromList
        [ (aId, smtConstructor aId [] testSort)
        , ( aSort0Id, smtConstructor aSort0Id [] testSort1)
        , ( aSort1Id, smtConstructor aSort1Id [] testSort1)
        , ( aSubsortId, smtConstructor aSubsortId [] subSort)
        , ( aSubOthersortId, smtConstructor aSubOthersortId [] subSubsort)
        , ( aSubSubsortId, smtConstructor aSubSubsortId [] subSubsort)
        , ( aTopSortId, smtConstructor aTopSortId [] topSort)
        , ( aOtherSortId, smtConstructor aOtherSortId [] otherSort)
        , ( bId, smtConstructor bId [] testSort)
        , ( bSort0Id, smtConstructor bSort0Id [] testSort0)
        , ( cId, smtConstructor cId [] testSort)
        , ( dId, smtConstructor dId [] testSort)
        , ( eId, smtConstructor eId [] testSort)
        , ( constr00Id, smtConstructor constr00Id [] testSort)
        , ( constr10Id, smtConstructor constr10Id [testSort] testSort)
        , ( constr11Id, smtConstructor constr11Id [testSort] testSort)
        , ( constr20Id, smtConstructor constr20Id [testSort, testSort] testSort)
        ,   ( functionalConstr10Id
            , smtConstructor functionalConstr10Id [testSort] testSort
            )
        ,   ( functionalConstr11Id
            , smtConstructor functionalConstr11Id [testSort] testSort
            )
        ,   ( functionalConstr12Id
            , smtConstructor functionalConstr12Id [testSort] testSort
            )
        ,   ( functionalConstr20Id
            , smtConstructor functionalConstr20Id [testSort, testSort] testSort
            )
        ,   ( functionalConstr21Id
            , smtConstructor functionalConstr21Id [testSort, testSort] testSort
            )
        ,   ( functionalConstr30Id
            , smtConstructor
                functionalConstr30Id
                [testSort, testSort, testSort]
                testSort
            )
        ,   ( functionalTopConstr20Id
            , smtConstructor
                functionalTopConstr21Id [testSort, testSort] testSort
            )
        ,   ( functionalTopConstr21Id
            , smtConstructor
                functionalTopConstr21Id [testSort, testSort] testSort
            )
        , ( lessIntId, smtBuiltinSymbol "<" [intSort, intSort] boolSort)
        , ( greaterEqIntId, smtBuiltinSymbol ">=" [intSort, intSort] boolSort)
        , ( sigmaId, smtConstructor sigmaId [testSort, testSort] testSort)
        ]
    }

testSortId :: Id
testSortId = testId "testSort"
testSort0Id :: Id
testSort0Id = testId "testSort0"
testSort1Id :: Id
testSort1Id = testId "testSort1"
topSortId :: Id
topSortId = testId "topSort"
subSortId :: Id
subSortId = testId "subSort"
subOthersortId :: Id
subOthersortId = testId "subOthersort"
subSubsortId :: Id
subSubsortId = testId "subSubsort"
otherSortId :: Id
otherSortId = testId "otherSort"
intSortId :: Id
intSortId = testId "intSort"
boolSortId :: Id
boolSortId = testId "boolSort"
stringSortId :: Id
stringSortId = testId "stringSort"

testSort :: Sort
testSort =
    SortActualSort SortActual
        { sortActualName  = testSortId
        , sortActualSorts = []
        }

testSort0 :: Sort
testSort0 =
    SortActualSort SortActual
        { sortActualName  = testSort0Id
        , sortActualSorts = []
        }

testSort1 :: Sort
testSort1 =
    SortActualSort SortActual
        { sortActualName  = testSort1Id
        , sortActualSorts = []
        }

topSort :: Sort
topSort =
    SortActualSort SortActual
        { sortActualName  = topSortId
        , sortActualSorts = []
        }

subSort :: Sort
subSort =
    SortActualSort SortActual
        { sortActualName  = subSortId
        , sortActualSorts = []
        }

subOthersort :: Sort
subOthersort =
    SortActualSort SortActual
        { sortActualName  = subOthersortId
        , sortActualSorts = []
        }

subSubsort :: Sort
subSubsort =
    SortActualSort SortActual
        { sortActualName  = subSubsortId
        , sortActualSorts = []
        }

otherSort :: Sort
otherSort =
    SortActualSort SortActual
        { sortActualName = otherSortId
        , sortActualSorts = []
        }

mapSort :: Sort
mapSort =
    SortActualSort SortActual
        { sortActualName  = testId "mapSort"
        , sortActualSorts = []
        }

setSort :: Sort
setSort =
    SortActualSort SortActual
        { sortActualName  = testId "setSort"
        , sortActualSorts = []
        }

listSort :: Sort
listSort =
    SortActualSort SortActual
        { sortActualName  = testId "listSort"
        , sortActualSorts = []
        }

intSort :: Sort
intSort =
    SortActualSort SortActual
        { sortActualName  = intSortId
        , sortActualSorts = []
        }

stringSort :: Sort
stringSort =
    SortActualSort SortActual
        { sortActualName  = stringSortId
        , sortActualSorts = []
        }

boolSort :: Sort
boolSort =
    SortActualSort SortActual
        { sortActualName  = boolSortId
        , sortActualSorts = []
        }

subsorts :: [(Sort, Sort)]
subsorts =
    [ (subSubsort, subSort)
    , (subSubsort, topSort)
    , (subSort, topSort)
    , (subSubsort, otherSort)
    , (subOthersort, otherSort)
    , (otherSort, topSort)
    ]

builtinMap
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => [(TermLike variable, TermLike variable)]
    -> TermLike variable
builtinMap elements = framedMap elements []

framedMap
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => [(TermLike variable, TermLike variable)]
    -> [variable]
    -> TermLike variable
framedMap elements (map Internal.mkVar -> opaque) =
    Internal.mkBuiltin $ Domain.BuiltinMap Domain.InternalAc
        { builtinAcSort = mapSort
        , builtinAcUnit = unitMapSymbol
        , builtinAcElement = elementMapSymbol
        , builtinAcConcat = concatMapSymbol
        , builtinAcChild =
            Domain.NormalizedMap Domain.NormalizedAc
                { elementsWithVariables = abstractElements
                , concreteElements
                , opaque
                }
        }
  where
    asConcrete element@(key, value) =
        (,) <$> Internal.asConcrete key <*> pure value
        & maybe (Left element) Right
    (abstractElements, Map.fromList -> concreteElements) =
        asConcrete . Bifunctor.second Domain.Value <$> elements
        & Either.partitionEithers

builtinList
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => [TermLike variable]
    -> TermLike variable
builtinList child =
    Internal.mkBuiltin $ Domain.BuiltinList Domain.InternalList
        { builtinListSort = listSort
        , builtinListUnit = unitListSymbol
        , builtinListElement = elementListSymbol
        , builtinListConcat = concatListSymbol
        , builtinListChild = Seq.fromList child
        }

builtinSet
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => [TermLike Concrete]
    -> TermLike variable
builtinSet child =
    Internal.mkBuiltin $ Domain.BuiltinSet Domain.InternalAc
        { builtinAcSort = setSort
        , builtinAcUnit = unitSetSymbol
        , builtinAcElement = elementSetSymbol
        , builtinAcConcat = concatSetSymbol
        , builtinAcChild = Domain.NormalizedSet Domain.NormalizedAc
            { elementsWithVariables = []
            , concreteElements =
                Map.fromList (map (\key -> (key, Domain.NoValue)) child)
            , opaque = []
            }
        }

builtinInt
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => Integer
    -> TermLike variable
builtinInt = Builtin.Int.asInternal intSort

builtinBool
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => Bool
    -> TermLike variable
builtinBool = Builtin.Bool.asInternal boolSort

emptyMetadataTools :: SmtMetadataTools Attribute.Symbol
emptyMetadataTools =
    Mock.makeMetadataTools
        [] -- attributesMapping
        [] -- headTypeMapping
        [] -- sortAttributesMapping
        [] -- subsorts
        emptySmtDeclarations

metadataTools :: GHC.HasCallStack => SmtMetadataTools Attribute.Symbol
metadataTools =
    Mock.makeMetadataTools
        attributesMapping
        sortAttributesMapping
        subsorts
        headSortsMapping
        smtDeclarations

termLikeSimplifier :: TermLikeSimplifier
termLikeSimplifier = Simplifier.create

axiomSimplifiers :: BuiltinAndAxiomSimplifierMap
axiomSimplifiers = Map.empty

predicateSimplifier :: PredicateSimplifier
predicateSimplifier = Simplifier.Predicate.create

env :: Env
env =
    Env
        { metadataTools = Test.Kore.Step.MockSymbols.metadataTools
        , simplifierTermLike = termLikeSimplifier
        , simplifierPredicate = predicateSimplifier
        , simplifierAxioms = axiomSimplifiers
        }
