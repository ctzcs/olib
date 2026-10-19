// 外层声明使用独立语法；HLSL 原文由 Zed 注入已安装的 HLSL 语言。
module.exports = grammar({
  name: 'olib_shader',
  extras: $ => [/\s/, $.comment],
  externals: $ => [$.hlsl_content],
  rules: {
    source_file: $ => repeat($.shader),
    shader: $ => seq('Shader', field('name', $.string), '{', repeat(choice(
      $.properties, $.pass, $.hlsl_include, $.directive
    )), '}'),
    properties: $ => seq('Properties', '{', repeat($.property), '}'),
    property: $ => seq(repeat($.attribute), field('name', $.property_name),
      '(', $.string, ',', $.property_type, ')', '=', $._value),
    attribute: $ => seq('[', field('name', $.identifier), '(', $._value, ')', ']'),
    property_type: $ => seq(choice('Range', 'Float', 'Vector2', 'Vector3', 'Color', '2D'),
      optional(seq('(', $.number, ',', $.number, ')'))),
    pass: $ => seq('Pass', field('name', $.string), '{', repeat(choice(
      $.directive, $.target, $.input, $.value_override, $.hlsl_program
    )), '}'),
    target: $ => seq('Target', '{', repeat(choice($.directive, $.size)), '}'),
    size: $ => seq('Size', $.number, $.number),
    directive: $ => seq(field('key', choice('Label', 'Preview', 'Output', 'Draw',
      'Cull', 'Blend', 'ZTest', 'ZWrite', 'Disabled', 'SpriteTexture',
      'Scale', 'Format', 'Depth', 'Samples', 'Clear')), $._value),
    input: $ => seq('Input', choice($.property_name, $.string), $.string, $.identifier),
    value_override: $ => seq('Value', choice($.property_name, $.string), $._value),
    hlsl_include: $ => seq('HLSLINCLUDE', optional($.hlsl_content), 'ENDHLSL'),
    hlsl_program: $ => seq('HLSLPROGRAM', optional($.hlsl_content), 'ENDHLSL'),
    _value: $ => choice($.string, $.number, $.vector, $.property_name, $.identifier),
    vector: $ => seq('(', $.number, repeat(seq(',', $.number)), ')'),
    property_name: _ => /_[A-Za-z_][A-Za-z_0-9]*/,
    identifier: _ => /[A-Za-z][A-Za-z_0-9]*|[23]D/,
    number: _ => /[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?/,
    string: _ => /"(?:[^"\\\n]|\\.)*"/,
    comment: _ => token(choice(/\/\/[^\n]*/, /\/\*[^*]*\*+([^/*][^*]*\*+)*\//)),
  }
});
