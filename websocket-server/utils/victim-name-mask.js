'use strict';

const THAI_PREFIX_MAP = {
  'นาย': 'นาย', 'นาง': 'นาง', 'นางสาว': 'นางสาว',
  'ด.ช.': 'ด.ช.', 'ด.ญ.': 'ด.ญ.', 'ไม่ระบุ': 'บุคคล',
};

const EN_PREFIX_MAP = {
  'นาย': 'Mr.', 'นาง': 'Mrs.', 'นางสาว': 'Ms.',
  'ด.ช.': 'Master', 'ด.ญ.': 'Miss', 'ไม่ระบุ': 'Person',
};

function isThaiText(s) {
  return /[\u0E00-\u0E7F]/.test(s || '');
}

function maskVictimName(prefix, firstName) {
  const name = (firstName || '').trim();
  if (!name) return `${THAI_PREFIX_MAP[prefix] || 'บุคคล'} (ไม่ทราบชื่อ)`;

  if (isThaiText(name)) {
    const LEADING_VOWELS = ['เ', 'แ', 'โ', 'ไ', 'ใ'];
    let ch = name[0];
    if (LEADING_VOWELS.includes(ch) && name.length > 1) ch = name[1];
    return `${THAI_PREFIX_MAP[prefix] || 'บุคคล'} ${ch}`;
  }
  return `${EN_PREFIX_MAP[prefix] || 'Person'} ${name[0].toUpperCase()}`;
}

function maskVictimNameWithDuplicate(prefix, firstName, existingMaskedNames) {
  const base = maskVictimName(prefix, firstName);
  if (!existingMaskedNames || existingMaskedNames.length === 0) return base;

  let result = base;
  let seq = 1;
  while (existingMaskedNames.includes(result)) {
    result = `${base} (${seq})`;
    seq++;
  }
  return result;
}

module.exports = { maskVictimName, maskVictimNameWithDuplicate, isThaiText };
