package org.kframework

import org.apache.commons.io.FileUtils
import org.junit.Assert.assertEquals
import org.junit.Test
import org.kframework.kore.Builders
import org.kframework.kore.implementation.DefaultBuilders
import org.kframework.kore.parser.{KoreToText, ParseError, TextToKore}

class TextToKoreTest {

  /**
    * Tests for parsing sorts.
    */
  @Test def test_sort_1(): Unit = {
    parseFromFile("test-sort-1.kore")
  }
  @Test def test_sort_2(): Unit = {
    parseFromFile("test-sort-2.kore")
  }
  @Test def test_sort_3(): Unit = {
    parseFromFile("test-sort-3.kore")
  }
  @Test def test_sort_4(): Unit = {
    parseFromFile("test-sort-4.kore")
  }

  /**
    * Tests for parsing symbols.
    */
  @Test def test_symbol_1(): Unit = {
    parseFromFile("test-symbol-1.kore")
  }
  @Test def test_symbol_2(): Unit = {
    parseFromFile("test-symbol-2.kore")
  }
  @Test def test_symbol_3(): Unit = {
    parseFromFile("test-symbol-3.kore")
  }
  @Test def test_symbol_4(): Unit = {
    parseFromFile("test-symbol-4.kore")
  }
  @Test def test_symbol_5(): Unit = {
    parseFromFile("test-symbol-5.kore")
  }
  @Test def test_symbol_6(): Unit = {
    parseFromFile("test-symbol-6.kore")
  }
  @Test def test_symbol_7(): Unit = {
    parseFromFile("test-symbol-7.kore")
  }
  @Test def test_symbol_8(): Unit = {
    parseFromFile("test-symbol-8.kore")
  }

  /**
    * Tests for parsing aliases.
    */
  @Test def test_alias_1(): Unit = {
    parseFromFile("test-alias-1.kore")
  }
  @Test def test_alias_2(): Unit = {
    parseFromFile("test-alias-2.kore")
  }
  @Test def test_alias_3(): Unit = {
    parseFromFile("test-alias-3.kore")
  }
  @Test def test_alias_4(): Unit = {
    parseFromFile("test-alias-4.kore")
  }
  @Test def test_alias_5(): Unit = {
    parseFromFile("test-alias-5.kore")
  }
  @Test def test_alias_6(): Unit = {
    parseFromFile("test-alias-6.kore")
  }
  @Test def test_alias_7(): Unit = {
    parseFromFile("test-alias-7.kore")
  }
  @Test def test_alias_8(): Unit = {
    parseFromFile("test-alias-8.kore")
  }

  /**
    * Tests for parsing patterns.
    */
  @Test def test_pattern_1(): Unit = {
    parseFromFile("test-pattern-1.kore")
  }
  @Test def test_pattern_2(): Unit = {
    parseFromFile("test-pattern-2.kore")
  }
  @Test def test_pattern_3(): Unit = {
    parseFromFile("test-pattern-3.kore")
  }
  @Test def test_pattern_4(): Unit = {
    parseFromFile("test-pattern-4.kore")
  }
  @Test def test_pattern_5(): Unit = {
    parseFromFile("test-pattern-5.kore")
  }
  @Test def test_pattern_6(): Unit = {
    parseFromFile("test-pattern-6.kore")
  }
  @Test def test_pattern_7(): Unit = {
    parseFromFile("test-pattern-7.kore")
  }
  @Test def test_pattern_8(): Unit = {
    parseFromFile("test-pattern-8.kore")
  }
  @Test def test_pattern_9(): Unit = {
    parseFromFile("test-pattern-9.kore")
  }
  @Test def test_pattern_10(): Unit = {
    parseFromFile("test-pattern-10.kore")
  }
  @Test def test_pattern_11(): Unit = {
    parseFromFile("test-pattern-11.kore")
  }
  @Test def test_pattern_12(): Unit = {
    parseFromFile("test-pattern-12.kore")
  }
  @Test def test_pattern_13(): Unit = {
    parseFromFile("test-pattern-13.kore")
  }
  @Test def test_pattern_14(): Unit = {
    parseFromFile("test-pattern-14.kore")
  }
  /**
    * Tests for parsing attributes.
    */
  @Test def test_attribute_1(): Unit = {
    parseFromFile("test-attribute-1.kore")
  }
  @Test def test_attribute_2(): Unit = {
    parseFromFile("test-attribute-2.kore")
  }


  /**
    * Comprehensive tests for parsing complete and meaningful modules.
    */


  @Test def bool(): Unit = {
    parseFromFile("bool.kore")
  }
  @Test def nat(): Unit = {
    parseFromFile("nat.kore")
  }
  @Test def list(): Unit = {
    parseFromFile("list.kore")
  }
  @Test def lambda(): Unit = {
    parseFromFile("lambda.kore")
  }
  @Test def imp(): Unit = {
    parseFromFile("imp.kore")
  }


  def strip(s: String): String = {
    trim(s.stripMargin)
  }

  def trim(s: String): String = {
    s.replaceAll("^\\s+|\\s+$", "") // s.replaceAll("^\\s+", "").replaceAll("\\s+$", "")
  }

  def parseFromStringWithExpected(s: String, expected: String): Unit = {
    val src = io.Source.fromString(s)
    try {
      parseTest(SourceFOS(src), s)
    } finally {
      src.close()
    }
  }

  def parseFromString(s: String): Unit = {
    val src = io.Source.fromString(s)
    try {
      parseTest(SourceFOS(src), s)
    } finally {
      src.close()
    }
  }

  def parseFromFile(file: String): Unit = {
    val f = FileUtils.toFile(getClass.getResource("/" + file))
    parseTest(FileFOS(f), FileUtils.readFileToString(f))
  }

  sealed trait FileOrSource
  case class FileFOS(x: java.io.File) extends FileOrSource
  case class SourceFOS(x: io.Source) extends FileOrSource

  /** Tests if parse is correct.
    *
    * Check:
    *   t == u(p(t))
    * otherwise,
    *   t == u(p(t)) modulo whitespaces
    *     and
    *   p(t) == p(u(p(t)))
    *
    * where:
    *   e in MiniKore
    *   t in String
    *   p : String -> MiniKore
    *   u : MiniKore -> String
    */
  def parseTest(src: FileOrSource, expected: String): Unit = {
    //TODO: Make test file parametric over builders.
    val builder: Builders = DefaultBuilders
    val begin = java.lang.System.nanoTime()
    val minikore = src match {
      case src: FileFOS => TextToKore(builder).parse(src.x)
      case src: SourceFOS => TextToKore(builder).parse(src.x)
    }
    val end = java.lang.System.nanoTime(); println(end - begin)
    val text = KoreToText(minikore)
    // val outputfile = new java.io.File("/tmp/x")
    // FileUtils.writeStringToFile(outputfile, text)
    if (expected == text) () // t == u(p(t))
    else if (trim(expected) == trim(text)) () // t == u(p(t)) modulo leading/trailing whitespaces
    else {
      assertEquals(expected.replaceAll("\\s+", ""), text.replaceAll("\\s+", "")) //   t  ==   u(p(t))  modulo whitespaces
      assertEquals(minikore, new TextToKore(builder).parse(io.Source.fromString(text))) // p(t) == p(u(p(t)))
    }
  }

//  @Test def errorTest(): Unit = {
//    new TextToMini().error('a', "abc") match {
//      case ParseError(msg) =>
//        assertEquals(
//          strip("""
//            |ERROR: Line 0: Column 0: Expected 'a', but abc
//            |null
//            |^
//            |"""),
//          msg)
//      case _ => assert(false)
//    }
//  }

}
