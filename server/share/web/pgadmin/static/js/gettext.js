/////////////////////////////////////////////////////////////
//
// pgAdmin 4 - PostgreSQL Tools
//
// Copyright (C) 2013 - 2025, The pgAdmin Development Team
// This software is released under the PostgreSQL Licence
//
//////////////////////////////////////////////////////////////

define(['translations'], function (translations) {

  let substitute = (raw, substitutions) => {
    let substitutionGroupsRegExp = /(%)([(])([a-zA-Z_]+)([)])(s)/g,
      res = raw;

    if (!raw)
      return raw;

    res = raw.replace(
      substitutionGroupsRegExp,
      function(_origin, _1, _2, substitutionName) {
        if (substitutionName in substitutions) {
          return substitutions[substitutionName];
        }
        return _origin;
      }
    );

    return res;
  };

  /***
   * This method behaves as a drop-in replacement for flask translation rendering.
   * It uses the same translation file under the hood and uses flask to determine the language.
   * It is slightly tweaked to work like sprintf
   * ex. translate("some %s text", "cool")
   *
   * @param {String} text
   */
  return function gettext(text) {

    let rawTranslation = translations[text] ? translations[text] : text;

    if(arguments.length === 1) {
      return rawTranslation;
    }

    if(arguments.length === 2 && typeof arguments[1] === 'object') {
      return substitute(rawTranslation, arguments[1]);
    }

    try {
      let replaceArgs = arguments;
      return rawTranslation.split('%s')
        .map(function(w, i) {
          if(i > 0) {
            if(i < replaceArgs.length) {
              return [replaceArgs[i], w].join('');
            } else {
              return ['%s', w].join('');
            }
          } else {
            return w;
          }
        })
        .join('');
    } catch(e) {
      console.error(e);
      return rawTranslation;
    }
  };
});
