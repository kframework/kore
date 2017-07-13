package org.kframework.kore.extended

import org.kframework.kore
import org.kframework.kore.Application
// Each Construct only has the minimal information required to derive everything.

object KnownSymbols {
  val PatternWithAttributes = kore.implementation.DefaultBuilders.Symbol("#")
}

object implicits {

  implicit class RichDefinition(val koreDefinition: kore.Definition) {
    lazy val modulesMap: Map[kore.ModuleName, kore.Module] = koreDefinition.modules.groupBy(_.name).mapValues(_.head)
  }

  implicit class RichModule(val koreModule: kore.Module)(implicit val d: kore.Definition) {

    import org.kframework.kore.implementation.{DefaultBuilders => db}

    lazy val localImports: Seq[kore.Module] = koreModule.sentences.collect({
      case kore.Import(m, _) => d.modulesMap(m)
    })

    lazy val imports: Seq[kore.Module] = localImports.flatMap(_.imports).toSet.toList ++ localImports

    lazy val localSentences = koreModule.sentences

    lazy val allSentences: Seq[kore.Sentence] = localSentences ++ importedSentences

    lazy val importedSentences: Seq[kore.Sentence] = imports.flatMap(_.allSentences)

    lazy val sorts: Seq[kore.Sort] = allSentences.collect({
      case kore.SymbolDeclaration(s, _, _, _) => s
      case kore.SortDeclaration(s, _) => s
    })

    lazy val localRules: Seq[kore.Rule] = localSentences.collect({
      case r@kore.Rule(_, _) => r
    })

    lazy val rules: Seq[kore.Rule] = localRules ++ importedRules

    lazy val importedRules: Seq[kore.Rule] = imports.flatMap(_.rules)

  }

  implicit class RichAttributes(val attributes: kore.Attributes) {

    def is(symbol: kore.Symbol): Boolean = findSymbol(symbol).isDefined

    def findSymbol(symbol: kore.Symbol): Option[kore.Pattern] = {
      attributes.patterns.toStream.collect({
        case p@kore.Application(`symbol`, _) => p
      }).headOption
    }

    def getSymbolValue(s: kore.Symbol): Option[kore.Value] = {
      findSymbol(s) flatMap {
        case kore.Application(_, Seq(kore.DomainValue(_, value))) => Some(value)
        case _ => None
      }
    }
  }

}


//Rewriter may need a module to begin with. Still a WIP.
//Needs a definition and a Module to start with.
trait Rewriter {
  def step(p: kore.Pattern, steps: Int = 1): kore.Pattern

  def execute(p: kore.Pattern): kore.Pattern
}

// Backend provides access to the definition (after its conversion) and it's set of Builders.
// Also acts as the Rewriter.
trait Backend extends kore.Definition with kore.Builders with Rewriter


//Way to Create a backend give a Kore Definition. Since Backends need the entire definition to
//Function, they can only provide Builders once they've processed the definition
trait BackendCreator extends ((kore.Definition, kore.Module) => Backend)




