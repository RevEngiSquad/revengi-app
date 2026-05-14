package org.revengi.app.yarax

import org.revengi.abhi.yarax.Compiler
import org.revengi.abhi.yarax.Rules
import org.revengi.abhi.yarax.Scanner

class YaraxBridge {

    fun scanWithSource(source: String, filePath: String): String {
        val compiler = Compiler()
        val compileError = compiler.addSource(source)
        if (compileError != null) {
            compiler.close()
            return """{"error":"Compilation error: ${escapeJson(compileError)}"}"""
        }
        val rules: Rules
        try {
            rules = compiler.build()
        } catch (e: Exception) {
            compiler.close()
            return """{"error":"Build error: ${escapeJson(e.message ?: "Unknown error")}"}"""
        }
        try {
            val scanner = Scanner(rules)
            try {
                return scanner.scanFile(filePath)
            } finally {
                scanner.close()
            }
        } finally {
            rules.close()
        }
    }

    fun scanWithSourceBytes(source: String, data: ByteArray): String {
        val compiler = Compiler()
        val compileError = compiler.addSource(source)
        if (compileError != null) {
            compiler.close()
            return """{"error":"Compilation error: ${escapeJson(compileError)}"}"""
        }
        val rules: Rules
        try {
            rules = compiler.build()
        } catch (e: Exception) {
            compiler.close()
            return """{"error":"Build error: ${escapeJson(e.message ?: "Unknown error")}"}"""
        }
        try {
            val scanner = Scanner(rules)
            try {
                return scanner.scanBytes(data)
            } finally {
                scanner.close()
            }
        } finally {
            rules.close()
        }
    }

    fun compileFromSource(source: String): ByteArray {
        val compiler = Compiler()
        val compileError = compiler.addSource(source)
        if (compileError != null) {
            compiler.close()
            throw IllegalArgumentException("Compilation error: $compileError")
        }
        val rules: Rules
        try {
            rules = compiler.build()
        } catch (e: Exception) {
            compiler.close()
            throw e
        }
        try {
            return rules.serialize()
        } finally {
            rules.close()
        }
    }

    fun scanWithCompiledRules(serializedRules: ByteArray, filePath: String): String {
        val rules: Rules
        try {
            rules = Rules.deserialize(serializedRules)
        } catch (e: Exception) {
            return """{"error":"Deserialization error: ${escapeJson(e.message ?: "Unknown error")}"}"""
        }
        try {
            val scanner = Scanner(rules)
            try {
                return scanner.scanFile(filePath)
            } finally {
                scanner.close()
            }
        } finally {
            rules.close()
        }
    }

    fun scanWithCompiledRulesBytes(serializedRules: ByteArray, data: ByteArray): String {
        val rules: Rules
        try {
            rules = Rules.deserialize(serializedRules)
        } catch (e: Exception) {
            return """{"error":"Deserialization error: ${escapeJson(e.message ?: "Unknown error")}"}"""
        }
        try {
            val scanner = Scanner(rules)
            try {
                return scanner.scanBytes(data)
            } finally {
                scanner.close()
            }
        } finally {
            rules.close()
        }
    }

    fun validateSource(source: String): String {
        val compiler = Compiler()
        val compileError = compiler.addSource(source)
        if (compileError != null) {
            compiler.close()
            return """{"valid":false,"error":"${escapeJson(compileError)}"}"""
        }
        try {
            compiler.build()
        } catch (e: Exception) {
            return """{"valid":false,"error":"${escapeJson(e.message ?: "Unknown error")}"}"""
        }
        return """{"valid":true}"""
    }

    private fun escapeJson(s: String): String {
        val sb = StringBuilder(s.length)
        for (c in s) {
            when (c) {
                '"' -> sb.append("\\\"")
                '\\' -> sb.append("\\\\")
                '\n' -> sb.append("\\n")
                '\r' -> sb.append("\\r")
                '\t' -> sb.append("\\t")
                else -> {
                    if (c.code < 0x20) {
                        sb.append(String.format("\\u%04x", c.code))
                    } else {
                        sb.append(c)
                    }
                }
            }
        }
        return sb.toString()
    }
}