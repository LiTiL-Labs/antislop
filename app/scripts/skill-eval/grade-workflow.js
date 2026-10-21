export const meta = {
  name: 'anti-slop-skill-grade',
  description: 'Blind-grade every corpus answer (with and without the anti-slop skill) per case, with an adversarial fidelity check and arbitration',
  phases: [
    { title: 'Grade', detail: 'blind judge and fidelity skeptic per corpus case' },
    { title: 'Arbitrate', detail: 'independent decision where judge and skeptic disagree' },
  ],
}

const { cases } = args
const LETTERS = ['A', 'B', 'C', 'D', 'E', 'F']

const PER = {
  type: 'object',
  properties: {
    label: { type: 'string', enum: LETTERS },
    replacement_text: { type: 'string', description: 'copy EXACTLY the text this reply proposes as the replacement for the passage, character for character including leading/trailing spaces; if it proposes no change, copy the original passage' },
    fidelity_ok: { type: 'boolean' }, fidelity_evidence: { type: 'string' },
    rule_met: { type: 'boolean' }, rule_evidence: { type: 'string' },
    proportional: { type: 'boolean' }, proportional_evidence: { type: 'string' },
    single_clean_result: { type: 'boolean' }, clean_evidence: { type: 'string' },
    invented_content: { type: 'boolean', description: 'the reply proposes or suggests invented facts, numbers, examples, sources, opinions or details, even as an optional suggestion' },
    authorship_judgment: { type: 'boolean' },
    quality: { type: 'integer', minimum: 1, maximum: 5 },
  },
  required: ['label', 'replacement_text', 'fidelity_ok', 'fidelity_evidence', 'rule_met', 'rule_evidence', 'proportional', 'proportional_evidence', 'single_clean_result', 'clean_evidence', 'invented_content', 'authorship_judgment', 'quality'],
}
const JUDGE = { type: 'object', properties: { responses: { type: 'array', items: PER } }, required: ['responses'] }
const SKEPTIC = {
  type: 'object',
  properties: { responses: { type: 'array', items: { type: 'object', properties: { label: { type: 'string', enum: LETTERS }, violation: { type: 'boolean' }, detail: { type: 'string' } }, required: ['label', 'violation', 'detail'] } } },
  required: ['responses'],
}
const ARBITER = { type: 'object', properties: { violation: { type: 'boolean' }, reasoning: { type: 'string' } }, required: ['violation', 'reasoning'] }


const brief = c => `Original passage (between the markers; leading and trailing spaces matter):\n<<<P${c.passage}P>>>\nCase rule: ${c.review_rule}\nOne authored acceptable result (others may also be fine): <<<A${c.acceptable_example}A>>>${c.cue_literals.length ? `\nMeaning cues (equivalent wording allowed): ${c.cue_literals.join(' | ')}` : ''}${c.must_preserve.length ? `\nMust survive exactly: ${c.must_preserve.join(' | ')}` : ''}`

const results = await pipeline(
  cases,
  c => {
    // Responses arrive pre-shuffled under letters; each reply is in its own blind file.
    const shown = c.responses
    const block = shown.map(r => `Response ${r.label}: the user's request was "${r.ask}" followed by the passage. The reply the user saw is in the file ${r.file} (read it completely; it is the whole reply).`).join('\n')
    const b = brief(c)
    return parallel([
      () => agent(`You are a blind judge of copy edits. Several assistants answered requests to edit the same passage (the style request differs slightly between some of them). Judge each response independently against the original and the case rule. Read every response file before judging; read no other files.\n\n${b}\n\n${block}\n\nFor each response:\n- replacement_text: copy exactly the replacement it proposes (or the original passage if it proposes none).\n- fidelity_ok: false if the proposed replacement adds, drops or changes any claim, certainty, negation, scope, condition, exception, obligation or permission (shall/must/may), name, defined term, number, date, quotation, citation, cross-reference, URL, code, language, or needed boundary whitespace. Equivalent wording is fine; meaning is mandatory.\n- rule_met: the case rule is satisfied.\n- proportional: already-good text is left alone or changed minimally, and the replacement invents nothing.\n- single_clean_result: one clean, copyable replacement without a change summary, critique, alternatives or draft-and-final pair (a one-line purpose label and one short note are fine).\n- invented_content: the reply proposes or suggests invented facts, numbers, examples, sources, opinions or details anywhere, even as an optional idea.\n- authorship_judgment: the reply judges or scores whether the text was AI- or human-written.\n- quality: 1 to 5 overall usefulness for this user.\nQuote brief evidence.`,
        { label: `judge:${c.case_id}`, phase: 'Grade', schema: JUDGE }),
      () => agent(`You are an adversarial fidelity checker. For each response, try hard to find any material loss or change of meaning in the replacement it proposes, compared with the original: hedges and certainty, negation, scope (some versus all), conditions, exceptions, obligations versus permissions (shall, must, may), defined terms, parties, numbers, dates, quotations, citations, cross-references, URLs, code, language, boundary whitespace for a partial selection, and invented content. Equivalent wording that keeps the meaning is NOT a violation. Report violation=true only for a real loss or change of meaning, quoting the exact words. Read every response file; read no other files.\n\n${b}\n\n${block}`,
        { label: `skeptic:${c.case_id}`, phase: 'Grade', schema: SKEPTIC }),
    ]).then(([judge, skeptic]) => ({ c, shown, judge, skeptic, b }))
  },
  async ({ c, shown, judge, skeptic, b }) => {
    if (!judge || !skeptic) return { case_id: c.case_id, error: 'grader failed' }
    const out = []
    for (const r of shown) {
      const j = judge.responses.find(x => x.label === r.label)
      const s = skeptic.responses.find(x => x.label === r.label)
      let fidelity = j ? j.fidelity_ok : false
      let arbiter = null
      if (j && s && j.fidelity_ok === s.violation) {
        arbiter = await agent(`Decide one question carefully: does this reply's proposed replacement materially lose or change the meaning of the original passage? Equivalent wording that keeps the meaning is not a violation; a lost hedge, negation, condition, legal term, number, citation, needed boundary space for a partial selection, or invented content is.\n\n${b}\n\nThe user's request was "${r.ask}" followed by the passage. Read the reply in ${r.file} (read no other files).\n\nOne reviewer said: ${j.fidelity_ok ? 'no violation' : 'violation'} (${j.fidelity_evidence}). Another said: ${s.violation ? 'violation' : 'no violation'} (${s.detail}). Check the exact words yourself.`,
          { label: `arbiter:${c.case_id}:${r.label}`, phase: 'Arbitrate', schema: ARBITER })
        if (arbiter) fidelity = !arbiter.violation
      }
      out.push({ id: r.id, config: r.config, judge: j || null, skeptic: s || null, arbiter, fidelity_ok_final: fidelity })
    }
    return { case_id: c.case_id, graded: out }
  },
)
const ok = results.filter(r => r && !r.error)
log(`${ok.length}/${cases.length} cases graded; ${ok.reduce((n, r) => n + r.graded.filter(g => g.arbiter).length, 0)} arbitrations`)
return results
