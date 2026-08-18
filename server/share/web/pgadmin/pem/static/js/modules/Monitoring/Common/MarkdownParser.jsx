///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';

const rules = [
  // Headings
  [/#{6}\s?([^\n]+)/g, (_, p1) => <h6>{p1}</h6>],
  [/#{5}\s?([^\n]+)/g, (_, p1) => <h5>{p1}</h5>],
  [/#{4}\s?([^\n]+)/g, (_, p1) => <h4>{p1}</h4>],
  [/#{3}\s?([^\n]+)/g, (_, p1) => <h3>{p1}</h3>],
  [/#{2}\s?([^\n]+)/g, (_, p1) => <h2>{p1}</h2>],
  [/#{1}\s?([^\n]+)/g, (_, p1) => <h1>{p1}</h1>],

  // Bold and italic
  [/\*\*([^*]+)\*\*/g, (_, p1) => <strong>{p1}</strong>],
  [/\*([^*]+)\*/g, (_, p1) => <em>{p1}</em>],
  [/__([^_]+)__/g, (_, p1) => <strong>{p1}</strong>],
  [/_([^_`]+)_/g, (_, p1) => <em>{p1}</em>],

  // Code highlight
  [
    /`([^`]+)`/g,
    (_, p1) => (
      <code
        style={{
          backgroundColor: 'grey',
          color: 'black',
          borderRadius: '3px',
          padding: '0 2px',
        }}
      >
        {p1}
      </code>
    ),
  ],

  // Link
  [
    /\[([^\]]+)\]\(([^)]+)\)/g,
    (_, text, href) => (
      <a href={href} style={{ color: '#2A5DB0', textDecoration: 'none' }}>
        {text}
      </a>
    ),
  ],

  // Images
  [
    /!\[([^\]]+)\]\(([^)]+)\s*"([^"]+)"\)/g,
    (_, alt, src, title) => <img src={src} alt={alt} title={title} />,
  ],
];

function parseLine(line, index) {
  let elements = [line];

  rules.forEach(([regex, replacer]) => {
    elements = elements.flatMap((el, i) => {
      if (typeof el !== 'string') return [el];

      const parts = [];
      let lastIndex = 0;
      let match;
      while ((match = regex.exec(el)) !== null) {
        if (match.index > lastIndex) {
          parts.push(el.slice(lastIndex, match.index));
        }
        parts.push(
          React.cloneElement(replacer(...match), {
            key: `${index}-${i}-${match.index}`,
          })
        );
        lastIndex = match.index + match[0].length;
      }

      if (lastIndex < el.length) {
        parts.push(el.slice(lastIndex));
      }

      return parts;
    });
  });

  return elements;
}

const MarkdownParser = ({ description = '' }) => {
  const lines = description.split(/\n/);

  return lines.map((line, index) => (
    <React.Fragment key={index}>
      {parseLine(line, index)}
      <br />
    </React.Fragment>
  ));
};

export default MarkdownParser;
