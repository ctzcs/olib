// 只提取 HLSL 区间，单行 ENDHLSL 以外的内容保持原样。
#include "tree_sitter/parser.h"
#include <stddef.h>

void *tree_sitter_olib_shader_external_scanner_create(void) { return NULL; }
void tree_sitter_olib_shader_external_scanner_destroy(void *p) { (void)p; }
unsigned tree_sitter_olib_shader_external_scanner_serialize(void *p, char *buffer) {
    (void)p; (void)buffer; return 0;
}
void tree_sitter_olib_shader_external_scanner_deserialize(void *p, const char *buffer, unsigned n) {
    (void)p; (void)buffer; (void)n;
}

bool tree_sitter_olib_shader_external_scanner_scan(void *p, TSLexer *lexer, const bool *valid) {
    (void)p;
    if (!valid[0]) return false;
    bool content = false, block_comment = false, line_comment = false;
    bool line_start = lexer->get_column(lexer) == 0;
    int32_t quote = 0;
    lexer->result_symbol = 0;
    while (!lexer->eof(lexer)) {
        lexer->mark_end(lexer);
        if (line_start && !block_comment && !quote) {
            while (lexer->lookahead == ' ' || lexer->lookahead == '\t' || lexer->lookahead == '\r')
                lexer->advance(lexer, false);
            const char *end = "ENDHLSL";
            unsigned i = 0;
            while (end[i] && lexer->lookahead == end[i]) {
                lexer->advance(lexer, false);
                i++;
            }
            if (!end[i]) {
                while (lexer->lookahead == ' ' || lexer->lookahead == '\t' || lexer->lookahead == '\r')
                    lexer->advance(lexer, false);
                if (lexer->lookahead == '\n' || lexer->eof(lexer)) return content;
            }
            line_start = false;
        }
        int32_t c = lexer->lookahead;
        if (lexer->eof(lexer)) break;
        lexer->advance(lexer, false);
        content = true;
        if (c == '\n') {
            line_start = true;
            line_comment = false;
        }
        if (line_comment) continue;
        if (block_comment) {
            if (c == '*' && lexer->lookahead == '/') {
                lexer->advance(lexer, false);
                block_comment = false;
            }
        } else if (quote) {
            if (c == '\\' && !lexer->eof(lexer)) lexer->advance(lexer, false);
            else if (c == quote) quote = 0;
        } else if (c == '/' && lexer->lookahead == '*') {
            lexer->advance(lexer, false);
            block_comment = true;
        } else if (c == '/' && lexer->lookahead == '/') {
            lexer->advance(lexer, false);
            line_comment = true;
        } else if (c == '"' || c == '\'') quote = c;
    }
    lexer->mark_end(lexer);
    return content;
}
