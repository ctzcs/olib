package encoding
/*
csv_mgr := encoding.Csv_Manager{}
encoding.csv_manager_init(&csv_mgr)
defer encoding.csv_manager_destroy(&csv_mgr)
tables := load_csv_tables(&csv_mgr)
defer destroy_csv_tables(&tables)
fmt.println(tables.leaf_config.by_kind[.Normal]^)
fmt.println(tables.leaf_config.by_kind[.Normal].tier_scores)
*/

import "core:encoding/csv"
import "core:reflect"
import "core:strings"
import "core:strconv"
import "core:os"
import "core:slice"

Csv_Error :: enum {
    None,
    File_Not_Found,
    Empty,
    Parse_Error,
}

Csv_Document :: struct {
    headers: []string,
    rows:    [dynamic][]string,
}

Csv_Manager :: struct {
    documents: map[string]^Csv_Document,
}

csv_manager_init :: proc(m: ^Csv_Manager) {
    m^ = Csv_Manager{}
}

csv_manager_destroy :: proc(m: ^Csv_Manager) {
    for _, doc in m.documents {
        delete(doc.rows)
        free(doc)
    }
    delete(m.documents)
}

// 读 CSV 文件，缓存到 manager
csv_manager_load :: proc(m: ^Csv_Manager, path: string) -> (^Csv_Document, Csv_Error) {
    if doc, ok := m.documents[path]; ok {
        return doc, .None
    }

    data, os_err := os.read_entire_file_from_path(path, context.allocator)
    if os_err != nil {
        return nil, .File_Not_Found
    }
    defer delete(data)

    records, csv_err := csv.read_all_from_string(string(data))
    if csv_err != nil {
        return nil, .Parse_Error
    }
    defer delete(records)

    if len(records) == 0 {
        return nil, .Empty
    }

    doc := new(Csv_Document)
    doc.headers = slice.clone(records[0])
    for i in 1..<len(records) {
        append(&doc.rows, slice.clone(records[i]))
    }

    m.documents[path] = doc
    return doc, .None
}

// 单行配置：把第一个数据行填进 struct
csv_manager_load_struct :: proc(m: ^Csv_Manager, path: string, $T: typeid) -> (T, Csv_Error) {
    result := T{}
    doc, err := csv_manager_load(m, path)
    if err != .None {
        return result, err
    }
    if len(doc.rows) == 0 {
        return result, .Empty
    }
    csv_fill_struct(&result, T, doc.headers, doc.rows[0])
    return result, .None
}

// 多行表：每行一个 struct，返回切片
csv_manager_load_table :: proc(m: ^Csv_Manager, path: string, $T: typeid) -> ([]T, Csv_Error) {
    doc, err := csv_manager_load(m, path)
    if err != .None {
        return nil, err
    }

    result := make([dynamic]T, 0, len(doc.rows))
    for row in doc.rows {
        item := T{}
        csv_fill_struct(&item, T, doc.headers, row)
        append(&result, item)
    }
    return result[:], .None
}

// 把一行 CSV 数据按表头映射到 struct 字段
csv_fill_struct :: proc(dst: rawptr, $T: typeid, headers: []string, row: []string) {
    col_map := make(map[string]int, len(headers))
    // Odin for-in: 第一个变量是元素，第二个是索引
    for h, i in headers {
        col_map[strings.trim_space(h)] = i
    }

    for field in reflect.struct_fields_zipped(T) {
        col_name := field.name
        if tag_val, ok := reflect.struct_tag_lookup(field.tag, "csv"); ok {
            col_name = tag_val
        }

        col_idx, ok := col_map[col_name]
        if !ok || col_idx >= len(row) {
            continue
        }

        str := strings.trim_space(row[col_idx])
        if len(str) == 0 {
            continue
        }

        csv_set_field(dst, field, str)
    }

    delete(col_map)
}

// 按字段类型把字符串写入 struct 字段
csv_set_field :: proc(struct_ptr: rawptr, field: reflect.Struct_Field, str: string) -> bool {
    ptr := rawptr(uintptr(struct_ptr) + field.offset)
    return csv_set_value(ptr, field.type.id, str)
}

// 按类型 id 把字符串写入 ptr 指向的内存
// 支持: 整数/浮点/布尔/string/enum/定长数组
// 数组单元格内用 '|' 分隔元素，例如 "10|20|30"
csv_set_value :: proc(ptr: rawptr, type_id: typeid, str: string) -> bool {
    kind := reflect.type_kind(type_id)
    size := reflect.size_of_typeid(type_id)

    #partial switch kind {
    case .Integer:
        v, ok := strconv.parse_i64(str)
        if !ok do return false
        switch size {
        case 1: (^(i8))(ptr)^  = i8(v)
        case 2: (^(i16))(ptr)^ = i16(v)
        case 4: (^(i32))(ptr)^ = i32(v)
        case 8: (^(i64))(ptr)^ = v
        case:  return false
        }

    case .Float:
        v, ok := strconv.parse_f64(str)
        if !ok do return false
        switch size {
        case 4: (^(f32))(ptr)^ = f32(v)
        case 8: (^(f64))(ptr)^ = v
        case:  return false
        }

    case .Boolean:
        lower := strings.to_lower(str)
        v := lower == "true" || str == "1"
        (^(bool))(ptr)^ = v

    case .String:
        (^(string))(ptr)^ = str

    case .Enum:
        ev, ok := reflect.enum_from_name_any(type_id, str)
        if !ok do return false
        // enum 底层是整数，按 enum 的字节宽度写入
        switch size {
        case 1: (^(u8))(ptr)^  = u8(ev)
        case 2: (^(u16))(ptr)^ = u16(ev)
        case 4: (^(u32))(ptr)^ = u32(ev)
        case 8: (^(u64))(ptr)^ = u64(ev)
        case:  return false
        }

    case .Array:
        // 单元格内用 '|' 分隔多个元素，不足补零，超出截断
        elem_id := reflect.typeid_elem(type_id)
        if elem_id == nil do return false
        elem_size := reflect.size_of_typeid(elem_id)
        if elem_size <= 0 do return false
        count := size / elem_size
        parts := strings.split(str, "|")
        defer delete(parts)
        for p, i in parts {
            if i >= count do break
            ep := rawptr(uintptr(ptr) + uintptr(i) * uintptr(elem_size))
            _ = csv_set_value(ep, elem_id, strings.trim_space(p))
        }

    case .Named:
        // distinct/命名类型：解包到基础类型后递归处理（枚举等会落到 .Enum 分支）
        base := reflect.type_info_base(type_info_of(type_id))
        if base == nil do return false
        return csv_set_value(ptr, base.id, str)

    case:
        return false
    }

    return true
}
