package com.paisa.paisa_mobile

import java.math.BigDecimal
import java.math.RoundingMode
import java.security.MessageDigest
import java.time.Instant

object FinancialSmsParser {
    private val amount = Regex("(?:INR|Rs\\.?|₹)\\s*([0-9,]+(?:\\.[0-9]{1,2})?)", RegexOption.IGNORE_CASE)
    private val debit = Regex("\\b(debited|spent|paid|sent|purchase|withdrawn)\\b", RegexOption.IGNORE_CASE)
    private val credit = Regex("\\b(credited|received|deposited|salary)\\b", RegexOption.IGNORE_CASE)
    private val financial = Regex("\\b(upi|a/c|acct|account|bank|txn|transaction|debited|credited)\\b", RegexOption.IGNORE_CASE)
    private val merchant = Regex("\\b(?:to|at|from)\\s+([a-z0-9@._ -]{2,60}?)(?=\\s+(?:on|ref|upi|txn|avl|bal|using|via)\\b|[.,]|$)", RegexOption.IGNORE_CASE)
    private val reference = Regex("\\b(?:ref(?:erence)?|utr|txn)\\s*(?:no|id)?[.: -]*([a-z0-9-]{6,40})", RegexOption.IGNORE_CASE)

    fun parse(sender: String, body: String, receivedAtMillis: Long): Map<String, Any>? {
        if (!financial.containsMatchIn(body) ||
            (!debit.containsMatchIn(body) && !credit.containsMatchIn(body))) return null

        val rawAmount = amount.find(body)?.groupValues?.get(1)?.replace(",", "") ?: return null
        val minor = try {
            BigDecimal(rawAmount).setScale(2, RoundingMode.HALF_UP).movePointRight(2).longValueExact()
        } catch (_: ArithmeticException) {
            return null
        }
        if (minor <= 0) return null

        val kind = if (debit.containsMatchIn(body)) "expense" else "income"
        val event = mutableMapOf<String, Any>(
            "sourceType" to "sms",
            "sourceHash" to sha256("$sender|$body|$receivedAtMillis"),
            "kind" to kind,
            "amountMinor" to (if (kind == "expense") -minor else minor).toString(),
            "occurredAt" to Instant.ofEpochMilli(receivedAtMillis).toString()
        )
        merchant.find(body)?.groupValues?.get(1)?.trim()?.takeIf { it.isNotEmpty() }?.let {
            event["merchant"] = it
        }
        reference.find(body)?.groupValues?.get(1)?.let { event["externalRef"] = it }
        return event
    }

    private fun sha256(value: String): String = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8))
        .joinToString("") { "%02x".format(it) }
}
