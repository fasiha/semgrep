(**
   Derive a javascript AST from a tree-sitter typescript CST.

   This is derived from generated code 'typescript/lib/Boilerplate.ml'
   in tree-sitter-lang and reuse functions from
   Parse_javascript_tree_sitter since the typescript tree-sitter grammar
   itself extends the tree-sitter javascript grammar.
*)

open Common
module AST = Ast_js
module H = Parse_tree_sitter_helpers
module G = AST_generic_
module PI = Parse_info
module H2 = AST_generic_helpers
open Ast_js

(*
   Development notes

   - Try to change the structure of this file as little as possible,
     since it's derived from generated code and we'll have to merge
     updates as the grammar changes.
   - Typescript is a superset of javascript.
   - We started by ignoring typescript-specific constructs and mapping
     the rest to a javascript AST.
*)

(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)

type env = unit H.env
let fb = PI.fake_bracket
let fake = PI.fake_info ""

let mk_functype (params, rett) =
  TyFun (params, rett)

let add_attributes_param attrs p =
  match p with
  | ParamClassic x -> ParamClassic { x with p_attrs = attrs @ x.p_attrs}
  (* TODO: ParamPattern can have decorators? *)
  | _ -> p

let todo _env _x =
  failwith "internal error: not implemented"

(*****************************************************************************)
(* Boilerplate converter *)
(*****************************************************************************)

(*
   We extend the javascript parsing module. Types are
   partially compatible.
*)
module JS_CST = Parse_javascript_tree_sitter.CST
module JS = Parse_javascript_tree_sitter
module CST = CST_tree_sitter_typescript (* typescript+tsx, merged *)

let accessibility_modifier (env : env) (x : CST.accessibility_modifier) =
  (match x with
   | `Public tok -> Public, JS.token env tok (* "public" *)
   | `Priv tok -> Private, JS.token env tok (* "private" *)
   | `Prot tok -> Protected, JS.token env tok (* "protected" *)
  )

let predefined_type (env : env) (x : CST.predefined_type) =
  (match x with
   | `Any tok -> JS.identifier env tok (* "any" *)
   | `Num tok -> JS.identifier env tok (* "number" *)
   | `Bool tok -> JS.identifier env tok (* "boolean" *)
   | `Str tok -> JS.identifier env tok (* "string" *)
   | `Symb tok -> JS.identifier env tok (* "symbol" *)
   | `Void tok -> JS.identifier env tok (* "void" *)
  )

let anon_choice_PLUSPLUS_e498e28 (env : env) (x : CST.anon_choice_PLUSPLUS_e498e28) =
  (match x with
   | `PLUSPLUS tok -> G.Incr, JS.token env tok (* "++" *)
   | `DASHDASH tok -> G.Decr, JS.token env tok (* "--" *)
  )

let anon_choice_type_2b11f6b (env : env) (x : CST.anon_choice_type_2b11f6b) =
  (match x with
   | `Type tok -> JS.token env tok (* "type" *)
   | `Typeof tok -> JS.token env tok (* "typeof" *)
  )

let automatic_semicolon (env : env) (tok : CST.automatic_semicolon) =
  JS.token env tok (* automatic_semicolon *)

let anon_choice_get_8fb02de (env : env) (x : CST.anon_choice_get_8fb02de) =
  (match x with
   | `Get tok -> Get, JS.token env tok (* "get" *)
   | `Set tok -> Set, JS.token env tok (* "set" *)
   | `STAR tok -> Generator, JS.token env tok (* "*" *)
  )

let reserved_identifier (env : env) (x : CST.reserved_identifier) =
  (match x with
   | `Decl tok -> JS.identifier env tok (* "declare" *)
   | `Name tok -> JS.identifier env tok (* "namespace" *)
   | `Type tok -> JS.identifier env tok (* "type" *)
   | `Public tok -> JS.identifier env tok (* "public" *)
   | `Priv tok -> JS.identifier env tok (* "private" *)
   | `Prot tok -> JS.identifier env tok (* "protected" *)
   | `Read tok -> JS.identifier env tok (* "readonly" *)
   | `Module tok -> JS.identifier env tok (* "module" *)
   | `Any tok -> JS.identifier env tok (* "any" *)
   | `Num tok -> JS.identifier env tok (* "number" *)
   | `Bool tok -> JS.identifier env tok (* "boolean" *)
   | `Str tok -> JS.identifier env tok (* "string" *)
   | `Symb tok -> JS.identifier env tok (* "symbol" *)
   | `Export tok -> JS.identifier env tok (* "export" *)
   | `Choice_get x ->
       (match x with
        | `Get tok -> JS.identifier env tok (* "get" *)
        | `Set tok -> JS.identifier env tok (* "set" *)
        | `Async tok -> JS.identifier env tok (* "async" *)
        | `Static tok -> JS.identifier env tok (* "static" *)
       )
  )

let anon_choice_COMMA_5194cb4 (env : env) (x : CST.anon_choice_COMMA_5194cb4) =
  (match x with
   | `COMMA tok -> JS.token env tok (* "," *)
   | `Choice_auto_semi x -> JS.semicolon env x
  )

(* TODO: types *)
let import_export_specifier (env : env) ((v1, v2, v3) : CST.import_export_specifier) =
  let _v1 =
    (match v1 with
     | Some x -> Some (anon_choice_type_2b11f6b env x)
     | None -> None)
  in
  JS.import_export_specifier env (v2, v3)

let rec anon_choice_type_id_42c0412 (env : env) (x : CST.anon_choice_type_id_42c0412) : ident list =
  (match x with
   | `Id tok -> [JS.identifier env tok] (* identifier *)
   | `Nested_id x -> nested_identifier env x
  )

and nested_identifier (env : env) ((v1, v2, v3) : CST.nested_identifier) =
  let v1 = anon_choice_type_id_42c0412 env v1 in
  let _v2 = JS.token env v2 (* "." *) in
  let v3 = JS.identifier env v3 (* identifier *) in
  v1 @ [v3]

let concat_nested_identifier (idents : ident list) : ident =
  let str = idents |> List.map fst |> String.concat "." in
  let tokens = List.map snd idents in
  let x, xs =
    match tokens with
    | [] -> assert false
    | x :: xs -> x, xs
  in
  str, PI.combine_infos x xs

(* 'import id = require(...)' are Commonjs-style import.
 * See https://www.typescriptlang.org/docs/handbook/2/modules.html#commonjs-style-import-and-export- for reference.
 * We translate them in regular typescript import.
 *  example:
 *      import zip = require("./ZipCodeValidator");
 *   => import * as zip from "./ZipCodeValidator"
 *
*)
let import_require_clause tk (env : env) ((v1, v2, v3, v4, v5, v6) : CST.import_require_clause) =
  let v1 = JS.identifier env v1 (* identifier *) in
  let _v2 = JS.token env v2 (* "=" *) in
  let _v3 = JS.identifier env v3 (* "require" *) in
  let _v4 = JS.token env v4 (* "(" *) in
  let v5 = JS.string_ env v5 in
  let _v6 = JS.token env v6 (* ")" *) in
  ModuleAlias(tk, v1, v5)

let literal_type (env : env) (x : CST.literal_type) : literal =
  (match x with
   | `Num_ (v1, v2) ->
       let (s, t1) =
         (match v1 with
          | `DASH tok -> JS.str env tok (* "-" *)
          | `PLUS tok -> JS.str env tok (* "+" *)
         )
       in
       let (s2, t2) = JS.str env v2 (* number *) in
       (* TODO: float_of_string_opt_also_from_hexoctbin *)
       Num (float_of_string_opt (s ^ s2), PI.combine_infos t1 [t2])
   | `Num tok ->
       let (s, t) = JS.str env tok in(* number *)
       (* TODO: float_of_string_opt_also_from_hexoctbin *)
       Num (float_of_string_opt s, t)
   | `Str x -> String (JS.string_ env x)
   | `True tok -> Bool (true, JS.token env tok) (* "true" *)
   | `False tok -> Bool (false, JS.token env tok) (* "false" *)
  )

let nested_type_identifier (env : env) ((v1, v2, v3) : CST.nested_type_identifier) : ident list =
  let v1 = anon_choice_type_id_42c0412 env v1 in
  let _v2 = JS.token env v2 (* "." *) in
  let v3 = JS.str env v3 (* identifier *) in
  v1 @ [ v3]

let anon_choice_rese_id_515394d (env : env) (x : CST.anon_choice_rese_id_515394d) : ident =
  (match x with
   | `Choice_decl x -> reserved_identifier env x
   | `Id tok -> JS.identifier env tok (* identifier *)
  )

let anon_choice_type_id_dd17e7d (env : env) (x : CST.anon_choice_type_id_dd17e7d) : ident =
  (match x with
   | `Id tok -> JS.identifier env tok (* identifier *)
   | `Choice_decl x -> reserved_identifier env x
  )

let anon_import_export_spec_rep_COMMA_import_export_spec_3a1421d (env : env) ((v1, v2) : CST.anon_import_export_spec_rep_COMMA_import_export_spec_3a1421d) =
  let v1 = import_export_specifier env v1 in
  let v2 =
    List.map (fun (v1, v2) ->
      let _v1 = JS.token env v1 (* "," *) in
      let v2 = import_export_specifier env v2 in
      v2
    ) v2
  in
  v1::v2

let export_clause (env : env) ((v1, v2, v3, v4) : CST.export_clause) =
  let _v1 = JS.token env v1 (* "{" *) in
  let v2 =
    (match v2 with
     | Some x ->
         anon_import_export_spec_rep_COMMA_import_export_spec_3a1421d env x
     | None -> [])
  in
  let _v3 =
    (match v3 with
     | Some tok -> Some (JS.token env tok) (* "," *)
     | None -> None)
  in
  let _v4 = JS.token env v4 (* "}" *) in
  v2

let named_imports (env : env) ((v1, v2, v3, v4) : CST.named_imports) =
  let _v1 = JS.token env v1 (* "{" *) in
  let v2 =
    (match v2 with
     | Some x ->
         anon_import_export_spec_rep_COMMA_import_export_spec_3a1421d env x
     | None -> [])
  in
  let _v3 =
    (match v3 with
     | Some tok -> Some (JS.token env tok) (* "," *)
     | None -> None)
  in
  let _v4 = JS.token env v4 (* "}" *) in
  (fun tok path ->
     v2 |> List.map (fun (n1, n2opt) -> Import (tok, n1, n2opt, path))
  )

let tuple_type_identifier (env : env) (x : CST.tuple_type_identifier) =
  (match x with
   | `Id tok -> JS.identifier env tok (* identifier *)
   | `Opt_id (v1, v2) ->
       let v1 = JS.identifier env v1 (* identifier *) in
       let _v2_TODO = JS.token env v2 (* "?" *) in
       v1
   | `Rest_id_ (v1, v2) ->
       let _v1_TODO = JS.token env v1 (* "..." *) in
       let v2 = JS.identifier env v2 (* identifier *) in
       v2
  )

let import_clause (env : env) (x : CST.import_clause) =
  (match x with
   | `Name_import x -> JS.namespace_import env x
   | `Named_imports x -> named_imports env x
   | `Id_opt_COMMA_choice_name_import (v1, v2) ->
       let v1 = JS.identifier env v1 (* identifier *) in
       let v2 =
         (match v2 with
          | Some (v1, v2) ->
              let _v1 = JS.token env v1 (* "," *) in
              let v2 =
                (match v2 with
                 | `Name_import x -> JS.namespace_import env x
                 | `Named_imports x -> named_imports env x
                )
              in
              v2
          | None ->
              (fun _t _path -> [])
         )
       in
       (fun t path ->
          let default = Import (t, (default_entity, snd v1), Some v1, path) in
          default :: v2 t path
       )
  )

let rec decorator_member_expression (env : env) ((v1, v2, v3) : CST.decorator_member_expression) : ident list =
  let v1 = anon_choice_type_id_b8f8ced env v1 in
  let _v2 = JS.token env v2 (* "." *) in
  let v3 = JS.identifier env v3 (* identifier *) in
  v1 @ [v3]

and anon_choice_type_id_b8f8ced (env : env) (x : CST.anon_choice_type_id_b8f8ced) : ident list =
  (match x with
   | `Id x -> [JS.identifier env x]
   | `Deco_member_exp x ->
       decorator_member_expression env x
  )

let rec parenthesized_expression (env : env) ((v1, v2, v3) : CST.parenthesized_expression) =
  let _v1 = JS.token env v1 (* "(" *) in
  let v2 =
    (match v2 with
     | `Exp_opt_type_anno (v1, v2) ->
         let v1 = expression env v1 in
         (match v2 with
          | Some x ->
              let (tok, ty) = type_annotation env x in
              Cast (v1, tok, ty)
          | None -> v1)
     | `Seq_exp x -> sequence_expression env x
    )
  in
  let _v3 = JS.token env v3 (* ")" *) in
  v2

and jsx_opening_element (env : env) ((v1, v2, v3, v4) : CST.jsx_opening_element) =
  let v1 = JS.token env v1 (* "<" *) in
  let v2 =
    (match v2 with
     | `Choice_choice_jsx_id x -> JS.jsx_attribute_name env x
     | `Choice_id_opt_type_args (v1, v2) ->
         let v1 = anon_choice_type_id_42c0412 env v1 in
         let id = concat_nested_identifier v1 in
         let _v2 =
           (match v2 with
            | Some x -> type_arguments env x |> PI.unbracket
            | None -> [])
         in
         id
    )
  in
  let v3 = List.map (jsx_attribute_ env) v3 in
  let v4 = JS.token env v4 (* ">" *) in
  v1, v2, v3, v4

and jsx_self_clos_elem (env : env) ((v1, v2, v3, v4, v5) : CST.jsx_self_closing_element) =
  let v1 = JS.token env v1 (* "<" *) in
  let v2 =
    (match v2 with
     | `Choice_choice_jsx_id x -> JS.jsx_attribute_name env x
     | `Choice_id_opt_type_args (v1, v2) ->
         let v1 = anon_choice_type_id_42c0412 env v1 in
         let id = concat_nested_identifier v1 in
         let _v2 =
           (match v2 with
            | Some x -> type_arguments env x |> PI.unbracket
            | None -> [])
         in
         id
    )
  in
  let v3 = List.map (jsx_attribute_ env) v3 in
  let v4 = JS.token env v4 (* "/" *) in
  let v5 = JS.token env v5 (* ">" *) in
  let t2 = PI.combine_infos v4 [v5] in
  v1, v2, v3, t2

and jsx_fragment (env : env) ((v1, v2, v3, v4, v5, v6) : CST.jsx_fragment)
  : xml =
  let v1 = JS.token env v1 (* "<" *) in
  let v2 = JS.token env v2 (* ">" *) in
  let v3 = List.map (jsx_child env) v3 in
  let v4 = JS.token env v4 (* "<" *) in
  let v5 = JS.token env v5 (* "/" *) in
  let v6 = JS.token env v6 (* ">" *) in
  let t1 = PI.combine_infos v1 [v2] in
  let t2 = PI.combine_infos v4 [v5;v6] in
  { xml_kind = XmlFragment (t1, t2); xml_attrs = []; xml_body = v3 }


and jsx_expression (env : env) ((v1, v2, v3) : CST.jsx_expression)
  : expr option bracket =
  let v1 = JS.token env v1 (* "{" *) in
  let v2 =
    (match v2 with
     | Some x ->
         Some (match x with
           | `Exp x -> expression env x
           | `Seq_exp x -> sequence_expression env x
           | `Spread_elem x ->
               let (t, e) = spread_element env x in
               Apply (IdSpecial (Spread, t), fb [e])
         )
     (* abusing { } in XML to just add comments, e.g. { /* lint-ignore */ } *)
     | None ->
         None
    )
  in
  let v3 = JS.token env v3 (* "}" *) in
  v1, v2, v3

and jsx_attribute_ (env : env) (x : CST.jsx_attribute_) : xml_attribute =
  (match x with
   | `Jsx_attr (v1, v2) ->
       let v1 = JS.jsx_attribute_name env v1 in
       let teq, v2 =
         match v2 with
         | Some (v1, v2) ->
             let v1bis = JS.token env v1 (* "=" *) in
             let v2 = jsx_attribute_value env v2 in
             v1bis, v2
         (* see https://www.reactenlightenment.com/react-jsx/5.7.html *)
         | None -> snd v1, L (Bool (true, snd v1))
       in
       XmlAttr (v1, teq, v2)
   (* less: we could enforce that it's only a Spread operation *)
   | `Jsx_exp x ->
       let x = jsx_expression_some env x in
       XmlAttrExpr x
  )

and jsx_expression_some env x =
  let (t1, eopt, t2) = jsx_expression env x in
  match eopt with
  | None ->
      JS.todo_any "jsx_expression_some got a None expr" t1 (Program [])
  | Some e -> (t1, e, t2)

and jsx_attribute_value (env : env) (x : CST.jsx_attribute_value) =
  (match x with
   | `Str x ->
       let s = JS.string_ env x in
       L (String s)
   | `Jsx_exp x ->
       let (_, e, _) = jsx_expression_some env x in
       e
   (* an attribute value can be a jsx element? *)
   | `Choice_jsx_elem x ->
       let xml = jsx_element_ env x in
       Xml xml
   | `Jsx_frag x ->
       let xml = jsx_fragment env x in
       Xml xml
  )

and jsx_child (env : env) (x : CST.jsx_child) : xml_body =
  (match x with
   | `Jsx_text tok ->
       let s = JS.str env tok (* pattern [^{}<>]+ *) in
       XmlText s
   | `Choice_jsx_elem x ->
       let xml = jsx_element_ env x in
       XmlXml xml
   | `Jsx_exp x ->
       let x = jsx_expression env x in
       XmlExpr x
   | `Jsx_frag x ->
       let xml = jsx_fragment env x in
       XmlXml xml
  )

and jsx_element_ (env : env) (x : CST.jsx_element_) : xml =
  (match x with
   | `Jsx_elem (v1, v2, v3) ->
       let (t0, tag, attrs, closing) = jsx_opening_element env v1 in
       let v2 = List.map (jsx_child env) v2 in
       let v3 = JS.jsx_closing_element env v3 in
       { xml_kind = XmlClassic (t0, tag, closing, snd v3);
         xml_attrs = attrs; xml_body = v2 }
   | `Jsx_self_clos_elem x ->
       let (t0, tag, attrs, closing) = jsx_self_clos_elem env x in
       { xml_kind = XmlSingleton (t0, tag, closing); xml_attrs = attrs;
         xml_body = [] }
  )

and destructuring_pattern (env : env) (x : CST.destructuring_pattern) : expr =
  (match x with
   | `Obj x -> let o = object_ env x in Obj o
   | `Array x -> array_ env x
  )

and variable_declaration (env : env) ((v1, v2, v3, v4) : CST.variable_declaration) : var list =
  let v1 = Var, JS.token env v1 (* "var" *) in
  let v2 = variable_declarator env v2 in
  let v3 =
    List.map (fun (v1, v2) ->
      let _v1 = JS.token env v1 (* "," *) in
      let v2 = variable_declarator env v2 in
      v2
    ) v3
  in
  let _v4 = JS.semicolon env v4 in
  let vars = v2::v3 in
  build_vars v1 vars

and function_ (env : env) ((v1, v2, v3, v4, v5) : CST.function_)
  : function_definition * ident option =
  let v1 =
    (match v1 with
     | Some tok -> [attr (Async, JS.token env tok)] (* "async" *)
     | None -> [])
  in
  let _v2 = JS.token env v2 (* "function" *) in
  let v3 =
    (match v3 with
     | Some tok -> Some (JS.identifier env tok) (* identifier *)
     | None -> None)
  in
  let (_tparams, (v4, tret)) = call_signature env v4 in
  let v5 = statement_block env v5 in
  { f_attrs = v1; f_params = v4; f_body = v5; f_rettype = tret },
  v3

and generic_type (env : env) ((v1, _v2) : CST.generic_type) : dotted_ident =
  let v1 =
    match v1 with
    | `Id tok -> [JS.identifier env tok] (* identifier *)
    | `Nested_type_id x -> nested_identifier env x
  in
  (* TODO:
     let v2 = type_arguments env v2 |> PI.unbracket
             |> List.map (fun x -> G.TypeArg x) in

     H2.name_of_ids ~name_typeargs:(Some v2) v1
  *)
  v1

and implements_clause (env : env) ((v1, v2, v3) : CST.implements_clause) : type_ list =
  let _v1 = JS.token env v1 (* "implements" *) in
  let v2 = type_ env v2 in
  let v3 =
    List.map (fun (v1, v2) ->
      let _v1 = JS.token env v1 (* "," *) in
      let v2 = type_ env v2 in
      v2
    ) v3
  in
  v2::v3

and anon_choice_exp_9818c1b (env : env) (x : CST.anon_choice_exp_9818c1b) =
  (match x with
   | `Exp x -> expression env x
   | `Spread_elem x ->
       let (t, e) = spread_element env x in
       Apply (IdSpecial (Spread, t), fb [e])
  )

and switch_default (env : env) ((v1, v2, v3) : CST.switch_default) =
  let v1 = JS.token env v1 (* "default" *) in
  let _v2 = JS.token env v2 (* ":" *) in
  let v3 = List.map (statement env) v3 |> List.flatten in
  Default (v1, stmt1 v3)

and binary_expression (env : env) (x : CST.binary_expression) : expr =
  (match x with
   | `Exp_AMPAMP_exp (v1, v2, v3) ->
       let v1 = expression env v1 in
       let v2 = JS.token env v2 (* "&&" *) in
       let v3 = expression env v3 in
       Apply (IdSpecial (ArithOp G.And, v2), fb [v1; v3])
   | `Exp_BARBAR_exp (v1, v2, v3) ->
       let v1 = expression env v1 in
       let v2 = JS.token env v2 (* "||" *) in
       let v3 = expression env v3 in
       Apply (IdSpecial (ArithOp G.Or, v2), fb [v1; v3])
   | `Exp_GTGT_exp (v1, v2, v3) ->
       let v1 = expression env v1 in
       let v2 = JS.token env v2 (* ">>" *) in
       let v3 = expression env v3 in
       Apply (IdSpecial (ArithOp G.LSR, v2), fb [v1; v3])
   | `Exp_GTGTGT_exp (v1, v2, v3) ->
       let v1 = expression env v1 in
       let v2 = JS.token env v2 (* ">>>" *) in
       let v3 = expression env v3 in
       Apply (IdSpecial (ArithOp G.ASR, v2), fb [v1; v3])
   | `Exp_LTLT_exp (v1, v2, v3) ->
       let v1 = expression env v1 in
       let v2 = JS.token env v2 (* "<<" *) in
       let v3 = expression env v3 in
       Apply (IdSpecial (ArithOp G.LSL, v2), fb [v1; v3])
   | `Exp_AMP_exp (v1, v2, v3) ->
       let v1 = expression env v1 in
       let v2 = JS.token env v2 (* "&" *) in
       let v3 = expression env v3 in
       Apply (IdSpecial (ArithOp G.BitAnd, v2), fb [v1; v3])
   | `Exp_HAT_exp (v1, v2, v3) ->
       let v1 = expression env v1 in
       let v2 = JS.token env v2 (* "^" *) in
       let v3 = expression env v3 in
       Apply (IdSpecial (ArithOp G.BitXor, v2), fb [v1; v3])
   | `Exp_BAR_exp (v1, v2, v3) ->
       let v1 = expression env v1 in
       let v2 = JS.token env v2 (* "|" *) in
       let v3 = expression env v3 in
       Apply (IdSpecial (ArithOp G.BitOr, v2), fb [v1; v3])
   | `Exp_PLUS_exp (v1, v2, v3) ->
       let v1 = expression env v1 in
       let v2 = JS.token env v2 (* "+" *) in
       let v3 = expression env v3 in
       Apply (IdSpecial (ArithOp G.Plus, v2), fb [v1; v3])
   | `Exp_DASH_exp (v1, v2, v3) ->
       let v1 = expression env v1 in
       let v2 = JS.token env v2 (* "-" *) in
       let v3 = expression env v3 in
       Apply (IdSpecial (ArithOp G.Minus, v2), fb [v1; v3])
   | `Exp_STAR_exp (v1, v2, v3) ->
       let v1 = expression env v1 in
       let v2 = JS.token env v2 (* "*" *) in
       let v3 = expression env v3 in
       Apply (IdSpecial (ArithOp G.Mult, v2), fb [v1; v3])
   | `Exp_SLASH_exp (v1, v2, v3) ->
       let v1 = expression env v1 in
       let v2 = JS.token env v2 (* "/" *) in
       let v3 = expression env v3 in
       Apply (IdSpecial (ArithOp G.Div, v2), fb [v1; v3])
   | `Exp_PERC_exp (v1, v2, v3) ->
       let v1 = expression env v1 in
       let v2 = JS.token env v2 (* "%" *) in
       let v3 = expression env v3 in
       Apply (IdSpecial (ArithOp G.Mod, v2), fb [v1; v3])
   | `Exp_STARSTAR_exp (v1, v2, v3) ->
       let v1 = expression env v1 in
       let v2 = JS.token env v2 (* "**" *) in
       let v3 = expression env v3 in
       Apply (IdSpecial (ArithOp G.Pow, v2), fb [v1; v3])
   | `Exp_LT_exp (v1, v2, v3) ->
       let v1 = expression env v1 in
       let v2 = JS.token env v2 (* "<" *) in
       let v3 = expression env v3 in
       Apply (IdSpecial (ArithOp G.Lt, v2), fb [v1; v3])
   | `Exp_LTEQ_exp (v1, v2, v3) ->
       let v1 = expression env v1 in
       let v2 = JS.token env v2 (* "<=" *) in
       let v3 = expression env v3 in
       Apply (IdSpecial (ArithOp G.LtE, v2), fb [v1; v3])
   | `Exp_EQEQ_exp (v1, v2, v3) ->
       let v1 = expression env v1 in
       let v2 = JS.token env v2 (* "==" *) in
       let v3 = expression env v3 in
       Apply (IdSpecial (ArithOp G.Eq, v2), fb [v1; v3])
   | `Exp_EQEQEQ_exp (v1, v2, v3) ->
       let v1 = expression env v1 in
       let v2 = JS.token env v2 (* "===" *) in
       let v3 = expression env v3 in
       Apply (IdSpecial (ArithOp G.PhysEq, v2), fb [v1; v3])
   | `Exp_BANGEQ_exp (v1, v2, v3) ->
       let v1 = expression env v1 in
       let v2 = JS.token env v2 (* "!=" *) in
       let v3 = expression env v3 in
       Apply (IdSpecial (ArithOp G.NotEq, v2), fb [v1; v3])
   | `Exp_BANGEQEQ_exp (v1, v2, v3) ->
       let v1 = expression env v1 in
       let v2 = JS.token env v2 (* "!==" *) in
       let v3 = expression env v3 in
       Apply (IdSpecial (ArithOp G.NotPhysEq, v2), fb [v1; v3])
   | `Exp_GTEQ_exp (v1, v2, v3) ->
       let v1 = expression env v1 in
       let v2 = JS.token env v2 (* ">=" *) in
       let v3 = expression env v3 in
       Apply (IdSpecial (ArithOp G.GtE, v2), fb [v1; v3])
   | `Exp_GT_exp (v1, v2, v3) ->
       let v1 = expression env v1 in
       let v2 = JS.token env v2 (* ">" *) in
       let v3 = expression env v3 in
       Apply (IdSpecial (ArithOp G.Gt, v2), fb [v1; v3])
   | `Exp_QMARKQMARK_exp (v1, v2, v3) ->
       let v1 = expression env v1 in
       let v2 = JS.token env v2 (* "??" *) in
       let v3 = expression env v3 in
       Apply (IdSpecial (ArithOp G.Nullish, v2), fb [v1; v3])
   | `Exp_inst_exp (v1, v2, v3) ->
       let v1 = expression env v1 in
       let v2 = JS.token env v2 (* "instanceof" *) in
       let v3 = expression env v3 in
       Apply (IdSpecial (Instanceof, v2), fb [v1; v3])
   | `Exp_in_exp (v1, v2, v3) ->
       let v1 = expression env v1 in
       let v2 = JS.token env v2 (* "in" *) in
       let v3 = expression env v3 in
       Apply (IdSpecial (In, v2), fb [v1; v3])
  )

and arguments (env : env) ((v1, v2, v3) : CST.arguments) : arguments =
  let v1 = JS.token env v1 (* "(" *) in
  let v2 =
    anon_opt_opt_choice_exp_rep_COMMA_opt_choice_exp_208ebb4 env v2
  in
  let v3 = JS.token env v3 (* ")" *) in
  v1, v2, v3

and generator_function_declaration (env : env) ((v1, v2, v3, v4, v5, v6, v7) : CST.generator_function_declaration) : definition =
  let v1 =
    (match v1 with
     | Some tok -> [attr (Async, JS.token env tok)] (* "async" *)
     | None -> [])
  in
  let _v2 = JS.token env v2 (* "function" *) in
  let v3 = [attr (Generator, JS.token env v3)] (* "*" *) in
  let v4 = JS.identifier env v4 (* identifier *) in
  let (_tparams, (v5, tret)) = call_signature env v5 in
  let v6 = statement_block env v6 in
  let _v7 =
    (match v7 with
     | Some tok -> Some (JS.token env tok) (* automatic_semicolon *)
     | None -> None)
  in
  let f = { f_attrs = v1 @ v3; f_params = v5; f_body = v6; f_rettype = tret }
  in
  basic_entity v4, FuncDef f

and variable_declarator (env : env) (x : CST.variable_declarator) =
  (match x with
   | `Choice_id_opt_type_anno_opt_init (v1, v2, v3) ->
       let v1 = anon_choice_type_id_21dd422 env v1 in
       let v2 =
         (match v2 with
          | Some x -> Some (type_annotation env x |> snd)
          | None -> None)
       in
       let v3 =
         (match v3 with
          | Some x -> Some (initializer_ env x)
          | None -> None)
       in
       v1, v2, v3
   | `Id_BANG_type_anno (v1, v2, v3) ->
       let v1 = Left (JS.identifier env v1 (* identifier *)) in
       (* definite assignment assertion
          TODO: add to AST? *)
       let _v2 = JS.token env v2 (* "!" *) in
       let v3 = type_annotation env v3 |> snd in
       v1, Some v3, None
  )

and sequence_expression (env : env) ((v1, v2, v3) : CST.sequence_expression) =
  let v1 = expression env v1 in
  let v2 = JS.token env v2 (* "," *) in
  let v3 =
    (match v3 with
     | `Seq_exp x -> sequence_expression env x
     | `Exp x -> expression env x
    )
  in
  Apply (IdSpecial (Seq, v2), fb [v1; v3])

and type_arguments (env : env) ((v1, v2, v3, v4, v5) : CST.type_arguments) : type_ list bracket =
  let v1 = JS.token env v1 (* "<" *) in
  let v2 = type_ env v2 in
  let v3 =
    List.map (fun (v1, v2) ->
      let _v1 = JS.token env v1 (* "," *) in
      let v2 = type_ env v2 in
      v2
    ) v3
  in
  let _v4 =
    (match v4 with
     | Some tok -> Some (JS.token env tok) (* "," *)
     | None -> None)
  in
  let v5 = JS.token env v5 (* ">" *) in
  v1, v2::v3, v5

and add_decorators xs property =
  match property with
  | Field fld -> Field { fld with fld_attrs = xs @ fld.fld_attrs }
  | FieldColon fld -> FieldColon { fld with fld_attrs = xs @ fld.fld_attrs }
  (* less: modify ast_js to allow decorator on those constructs? *)
  | FieldSpread _ | FieldPatDefault _
  | FieldEllipsis _
  | FieldTodo _
    -> property

(* TODO: types - class body can be just a signature. *)
and class_body (env : env) ((v1, v2, v3) : CST.class_body) : property list bracket =
  let v1 = JS.token env v1 (* "{" *) in
  let rec aux acc_decorators xs =
    match xs with
    | [] -> []
    | x::xs ->
        (match x with
         | `Deco x ->
             let attr = decorator env x in
             aux (attr::acc_decorators) xs

         | `Meth_defi_opt_choice_auto_semi (v1, v2) ->
             let v1 = method_definition env v1 in
             let _v2 =
               (match v2 with
                | Some x -> Some (JS.semicolon env x)
                | None -> None)
             in
             add_decorators (List.rev acc_decorators) v1::aux [] xs
         | `Choice_abst_meth_sign_choice_choice_auto_semi (v1, v2) ->
             let v1 =
               (match v1 with
                | `Abst_meth_sign x ->
                    (* TODO: types *)
                    let _v = abstract_method_signature env x in
                    None
                | `Index_sign x ->
                    let _t = index_signature env x in
                    None
                | `Meth_sign x ->
                    (* TODO: types *)
                    let _v = method_signature env x in
                    None
                | `Public_field_defi x ->
                    Some (public_field_definition env x)
               )
             in
             let _v2 =
               (match v2 with
                | `Choice_auto_semi x -> JS.semicolon env x
                | `COMMA tok -> JS.token env tok (* "," *)
               )
             in
             (match v1 with
              | None -> aux [] xs
              | Some x ->
                  add_decorators (List.rev acc_decorators) x::aux [] xs
             )
        )
  in
  let v2 = aux [] v2 in
  let v3 = JS.token env v3 (* "}" *) in
  v1, v2, v3

and type_parameter (env : env) ((v1, v2, v3) : CST.type_parameter) : type_parameter =
  let v1 = JS.str env v1 (* identifier *) in
  let _v2 =
    (match v2 with
     | Some x -> Some (constraint_ env x)
     | None -> None)
  in
  let _v3 =
    (match v3 with
     | Some x -> Some (default_type env x)
     | None -> None)
  in
  v1

and member_expression (env : env) ((v1, v2, v3) : CST.member_expression) : expr =
  let v1 = anon_choice_exp_6ded967 env v1 in
  (* TODO: distinguish optional chaining "?." from a simple access "." *)
  let v2 =
    match v2 with
    | `DOT tok (* "." *)
    | `QMARKDOT (* "?." *) tok -> JS.token env tok
  in
  let v3 = JS.identifier env v3 (* identifier *) in
  ObjAccess (v1, v2, PN v3)

and anon_choice_pair_bc93fa1 (env : env) (x : CST.anon_choice_pair_bc93fa1) : property =
  (match x with
   | `Pair (v1, v2, v3) ->
       let v1 = property_name env v1 in
       let _v2 = JS.token env v2 (* ":" *) in
       let v3 = expression env v3 in
       FieldColon {fld_name = v1; fld_attrs = []; fld_type = None; fld_body =Some v3}
   | `Spread_elem x ->
       let (t, e) = spread_element env x in
       FieldSpread (t, e)
   | `Meth_defi x -> method_definition env x

   | `Assign_pat (v1, v2, v3) ->
       let v1 =
         (match v1 with
          | `Choice_choice_decl x -> anon_choice_rese_id_515394d env x |> idexp
          | `Choice_obj x -> destructuring_pattern env x
         )
       in
       let v2 = JS.token env v2 (* "=" *) in
       let v3 = expression env v3 in
       FieldPatDefault (v1, v2, v3)

   (* { x } shorthand for { x: x }, like in OCaml *)
   | `Choice_id x ->
       let id = anon_choice_type_id_dd17e7d env x in
       FieldColon {fld_name = PN id; fld_attrs = []; fld_type = None;
                   fld_body = Some (idexp id) }
  )

and subscript_expression (env : env) ((v1, v2, v3, v4, v5) : CST.subscript_expression) : expr =
  let v1 = anon_choice_exp_6ded967 env v1 in
  let _v2 =
    match v2 with
    | None -> None
    | Some tok -> Some (JS.token env tok) (* "?." *)
  in
  let v3 = JS.token env v3 (* "[" *) in
  let v4 = expressions env v4 in
  let v5 = JS.token env v5 (* "]" *) in
  (* TODO: distinguish optional chaining "?." from a simple access "." *)
  ArrAccess (v1, (v3, v4, v5))

and initializer_ (env : env) ((v1, v2) : CST.initializer_) =
  let _v1 = JS.token env v1 (* "=" *) in
  let v2 = expression env v2 in
  v2

and primary_expression (env : env) (x : CST.primary_expression) : expr =
  (match x with
   | `This tok -> JS.this env tok (* "this" *)
   | `Super tok -> JS.super env tok (* "super" *)
   | `Id tok ->
       let id = JS.identifier env tok (* identifier *) in
       idexp_or_special id
   | `Choice_decl x ->
       let id = reserved_identifier env x in
       idexp id
   | `Num tok ->
       let n = JS.number env tok (* number *) in
       L (Num n)
   | `Str x ->
       let s = JS.string_ env x in
       L (String s)
   | `Temp_str x ->
       let t1, xs, t2 = template_string env x in
       Apply (IdSpecial (Encaps false, t1), (t1, xs, t2))
   | `Regex (v1, v2, v3, v4) ->
       let v1 = JS.token env v1 (* "/" *) in
       let s, t = JS.str env v2 (* regex_pattern *) in
       let v3 = JS.token env v3 (* "/" *) in
       let v4 =
         (match v4 with
          | Some tok -> [JS.token env tok] (* pattern [a-z]+ *)
          | None -> [])
       in
       let tok = PI.combine_infos v1 ([t; v3] @ v4) in
       L (Regexp (s, tok))
   | `True tok -> L (Bool (true, JS.token env tok) (* "true" *))
   | `False tok -> L (Bool (false, JS.token env tok) (* "false" *))
   | `Null tok -> IdSpecial (Null, JS.token env tok) (* "null" *)
   | `Unde tok -> IdSpecial (Undefined, JS.token env tok) (* "undefined" *)
   | `Import tok -> JS.identifier env tok (* import *) |> idexp
   | `Obj x -> let o = object_ env x in Obj o
   | `Array x -> array_ env x
   | `Func x ->
       let f, idopt = function_ env x in
       Fun (f, idopt)
   | `Arrow_func (v1, v2, v3, v4) ->
       let v1 =
         (match v1 with
          | Some tok -> [attr (Async, JS.token env tok)] (* "async" *)
          | None -> [])
       in
       let v2, tret =
         (match v2 with
          | `Choice_choice_decl x ->
              let id = anon_choice_rese_id_515394d env x in
              [ParamClassic (mk_param id)], None
          | `Call_sign x ->
              let (_tparams, (params, tret)) = call_signature env x in
              params, tret
         )
       in
       let v3 = JS.token env v3 (* "=>" *) in
       let v4 =
         (match v4 with
          | `Exp x ->
              let e = expression env x in
              Return (v3, Some e, PI.sc)
          | `Stmt_blk x -> statement_block env x
         )
       in
       let f = { f_attrs = v1; f_params = v2; f_body = v4; f_rettype = tret }
       in
       Fun (f, None)
   | `Gene_func (v1, v2, v3, v4, v5, v6) ->
       let v1 =
         (match v1 with
          | Some tok -> [Async, JS.token env tok] (* "async" *)
          | None -> [])
       in
       let _v2 = JS.token env v2 (* "function" *) in
       let v3 = [Generator, JS.token env v3] (* "*" *) in
       let v4 =
         (match v4 with
          | Some tok -> Some (JS.identifier env tok) (* identifier *)
          | None -> None)
       in
       let (_tparams, (v5, tret)) = call_signature env v5 in
       let v6 = statement_block env v6 in
       let attrs = (v1 @ v3) |> List.map attr in
       let f = { f_attrs = attrs; f_params = v5; f_body = v6; f_rettype = tret }
       in
       Fun (f, v4)
   | `Class (v1, v2, v3, v4, v5, v6) ->
       let v1 = List.map (decorator env) v1 in
       let v2 = JS.token env v2 (* "class" *) in
       let v3 =
         (match v3 with
          | Some tok -> Some (JS.identifier env tok) (* identifier *)
          | None -> None)
       in
       (* TODO types *)
       let _v4 =
         (match v4 with
          | Some x -> type_parameters env x
          | None -> [])
       in
       let c_extends, c_implements =
         (match v5 with
          | Some x -> class_heritage env x
          | None -> [], [])
       in
       let v6 = class_body env v6 in
       let class_ = { c_kind = G.Class, v2; c_attrs = v1;
                      c_extends; c_implements;
                      c_body = v6;
                    } in
       Class (class_, v3)
   | `Paren_exp x -> parenthesized_expression env x
   | `Subs_exp x -> subscript_expression env x
   | `Member_exp x -> member_expression env x
   | `Meta_prop (v1, v2, v3) ->
       let v1 = JS.token env v1 (* "new" *) in
       let v2 = JS.token env v2 (* "." *) in
       let v3 = JS.token env v3 (* "target" *) in
       let t = PI.combine_infos v1 [v2;v3] in
       IdSpecial (NewTarget, t)
   | `Call_exp x -> call_expression env x
  )

and call_expression (env : env) (x : CST.call_expression) =
  (match x with
   | `Exp_opt_type_args_choice_args (v1, v2, v3) ->
       let v1 = expression env v1 in
       (* TODO: types *)
       let _v2 =
         match v2 with
         | Some x -> type_arguments env x |> PI.unbracket
         | None -> []
       in
       let v3 =
         (match v3 with
          | `Args x ->
              let args = arguments env x in
              Apply (v1, args)
          | `Temp_str x ->
              let (t1, xs, t2) = template_string env x in
              Apply (IdSpecial (Encaps true, t1),
                     (t1, v1::xs, t2))
         )
       in
       v3
   | `Choice_this_QMARKDOT_opt_type_args_args (v1, v2, v3, v4) ->
       let v1 = primary_expression env v1 in
       let _v2 = JS.token env v2 (* "?." *) in
       (* TODO: types *)
       let _v3 =
         match v3 with
         | Some x -> type_arguments env x |> PI.unbracket
         | None -> []
       in
       let v4 = arguments env v4 in
       (* TODO: distinguish "?." from a simple application *)
       Apply (v1, v4)
  )

and anon_choice_prop_name_6cc9e4b (env : env) (x : CST.anon_choice_prop_name_6cc9e4b) =
  (match x with
   | `Prop_name x -> property_name env x, None
   | `Enum_assign (v1, v2) ->
       let v1 = property_name env v1 in
       let v2 = initializer_ env v2 in
       v1, Some v2
  )

and module__ (env : env) ((v1, v2) : CST.module__) =
  let v1 = (* module identifier *)
    (match v1 with
     | `Str x -> JS.string_ env x
     | `Id tok -> JS.identifier env tok (* identifier *)
     | `Nested_id x ->
         nested_identifier env x
         |> concat_nested_identifier
    )
  in
  let v2 = (* optional module body *)
    (match v2 with
     | Some x -> Some (statement_block env x)
     | None -> None)
  in
  (v1, v2)

and non_null_expression (env : env) ((v1, v2) : CST.non_null_expression) =
  let v1 = expression env v1 in
  let v2 = JS.token env v2 (* "!" *) in
  let special = ArithOp G.NotNullPostfix, v2 in
  Apply (IdSpecial special, fb [v1])

and expression_statement (env : env) ((v1, v2) : CST.expression_statement) =
  let v1 = expressions env v1 in
  let v2 = JS.semicolon env v2 in
  (v1, v2)

and catch_clause (env : env) ((v1, v2, v3) : CST.catch_clause) =
  let v1 = JS.token env v1 (* "catch" *) in
  let v3 = statement_block env v3 in
  let v2 =
    (match v2 with
     | Some (v1bis, v2, v3bis) ->
         let _v1 = JS.token env v1bis (* "(" *) in
         let v2 = anon_choice_type_id_21dd422 env v2 in
         let _v3 = JS.token env v3bis (* ")" *) in
         let pat =
           match v2 with
           | Left id -> idexp id
           | Right pat -> pat
         in
         BoundCatch (v1, pat, v3)
     | None -> UnboundCatch (v1, v3))
  in
  v2

and object_type (env : env) ((v1, v2, v3) : CST.object_type) =
  let v1 =
    (match v1 with
     | `LCURL tok -> JS.token env tok (* "{" *)
     | `LCURLBAR tok -> JS.token env tok (* "{|" *)
    )
  in
  let v2 =
    (match v2 with
     | Some (v1, v2, v3, v4) ->
         let _v1 =
           (match v1 with
            | Some x ->
                Some (match x with
                  | `COMMA tok -> JS.token env tok (* "," *)
                  | `SEMI tok -> JS.token env tok (* ";" *)
                )
            | None -> None)
         in
         let v2 = anon_choice_export_stmt_f90d83f env v2 in
         let v3 =
           List.map (fun (v1, v2) ->
             let _v1 = anon_choice_COMMA_5194cb4 env v1 in
             let v2 = anon_choice_export_stmt_f90d83f env v2 in
             v2
           ) v3
         in
         let _v4 =
           (match v4 with
            | Some x -> Some (anon_choice_COMMA_5194cb4 env x)
            | None -> None)
         in
         v2::v3
     | None -> [])
  in
  let v3 =
    (match v3 with
     | `RCURL tok -> JS.token env tok (* "}" *)
     | `BARRCURL tok -> JS.token env tok (* "|}" *)
    )
  in
  v1, v2, v3

and anon_choice_type_id_21dd422 (env : env) (x : CST.anon_choice_type_id_21dd422) =
  (match x with
   | `Id tok -> Left (JS.identifier env tok (* identifier *))
   | `Choice_obj x -> Right (destructuring_pattern env x)
  )

and template_string (env : env) ((v1, v2, v3) : CST.template_string) : expr list bracket =
  let v1 = JS.token env v1 (* "`" *) in
  let v2 =
    List.map (fun x ->
      (match x with
       | `Temp_chars tok -> L (String (JS.str env tok)) (* template_chars *)
       | `Esc_seq tok -> L (String (JS.str env tok)) (* escape_sequence *)
       | `Temp_subs x -> template_substitution env x
      )
    ) v2
  in
  let v3 = JS.token env v3 (* "`" *) in
  v1, v2, v3

and decorator (env : env) ((v1, v2) : CST.decorator) : attribute =
  let v1 = JS.token env v1 (* "@" *) in
  let ids, args_opt =
    (match v2 with
     | `Id x ->
         let id = JS.identifier env x in
         [id], None
     | `Deco_member_exp x ->
         let ids = decorator_member_expression env x in
         ids, None
     | `Deco_call_exp x ->
         let ids, args = decorator_call_expression env x in
         ids, Some args
    )
  in
  NamedAttr (v1, ids, args_opt)

and internal_module (env : env) ((v1, v2) : CST.internal_module) =
  let _v1 = JS.token env v1 (* "namespace" *) in
  let v2 = module__ env v2 in
  v2

and anon_opt_opt_choice_exp_rep_COMMA_opt_choice_exp_208ebb4 (env : env) (opt : CST.anon_opt_opt_choice_exp_rep_COMMA_opt_choice_exp_208ebb4) =
  (match opt with
   | Some (v1, v2) ->
       let v1 =
         (match v1 with
          | Some x -> [anon_choice_exp_9818c1b env x]
          | None -> [])
       in
       let v2 = anon_rep_COMMA_opt_choice_exp_ca698a5 env v2 in
       v1 @ v2
   | None -> [])

and for_header (env : env) ((v1, v2, v3, v4, v5, v6) : CST.for_header) =
  let _v1 = JS.token env v1 (* "(" *) in
  let v2 =
    (match v2 with
     | Some x ->
         Some (match x with
           | `Var tok -> Var, JS.token env tok (* "var" *)
           | `Let tok -> Let, JS.token env tok (* "let" *)
           | `Const tok -> Const, JS.token env tok (* "const" *)
         )
     | None -> None)
  in
  let v3 = anon_choice_paren_exp_9c42f0a env v3 in
  let var_or_expr =
    match v2 with
    | None -> Right v3
    | Some vkind ->
        let var = Ast_js.var_pattern_to_var vkind v3 (snd vkind) None in
        Left var
  in
  let v5 = expressions env v5 in
  let _v6 = JS.token env v6 (* ")" *) in
  let v4 =
    (match v4 with
     | `In tok -> ForIn (var_or_expr, JS.token env tok, v5) (* "in" *)
     | `Of tok -> ForOf (var_or_expr, JS.token env tok, v5) (* "of" *)
    )
  in
  v4

and anon_choice_exp_6ded967 (env : env) (x : CST.anon_choice_exp_6ded967) : expr =
  match x with
  | `Exp x -> expression env x
  | `Choice_this x -> primary_expression env x

and expression (env : env) (x : CST.expression) : expr =
  (match x with
   | `As_exp (v1, v2, v3) ->
       (* type assertion of the form 'exp as type' *)
       let v1 = expression env v1 in
       let v2 = JS.token env v2 (* "as" *) in
       (match v3 with
        | `Type x -> let x = type_ env x in
            TypeAssert (v1, v2, x)
        | `Temp_str x ->
            let (_, xs, _) = template_string env x in
            ExprTodo (("WeirdCastTemplateString", v2), v1::xs)
       )
   | `Non_null_exp x ->
       non_null_expression env x

   | `Inte_module x ->
       (* namespace (deprecated in favor of ES modules) *)
       (* TODO represent namespaces properly in the AST instead of the nonsense
          below. *)
       let name, opt_body = internal_module env x in
       (match opt_body with
        | Some body ->
            let fun_ = {
              f_attrs = []; f_params = []; f_body = body; f_rettype = None;
            } in
            Apply (Fun (fun_, Some name), fb [])
        | None ->
            idexp name
       )

   | `Super tok -> JS.super env tok (* "super" *)

   | `Type_asse (v1, v2) ->
       (* type assertion of the form <string>someValue *)
       let (t1, xs, _t2) = type_arguments env v1 in
       let v2 = expression env v2 in
       (match xs with
        | [t] -> TypeAssert (v2, t1, t)
        | _ -> raise (PI.Parsing_error t1)
       )
   | `Choice_this x -> primary_expression env x

   | `Choice_jsx_elem x ->
       let xml = jsx_element_ env x in
       Xml xml

   | `Jsx_frag x ->
       let xml = jsx_fragment env x in
       Xml xml

   | `Assign_exp (v1, v2, v3) ->
       let v1 = anon_choice_paren_exp_9c42f0a env v1 in
       let v2 = JS.token env v2 (* "=" *) in
       let v3 = expression env v3 in
       Assign (v1, v2, v3)
   | `Augm_assign_exp (v1, v2, v3) ->
       let lhs =
         (match v1 with
          | `Choice_member_exp x ->
              (match x with
               | `Member_exp x -> member_expression env x
               | `Subs_exp x -> subscript_expression env x
               | `Choice_decl x ->
                   let id = reserved_identifier env x in
                   idexp id
               | `Id tok ->
                   let id = JS.identifier env tok (* identifier *) in
                   idexp id
               | `Paren_exp x -> parenthesized_expression env x
              )
          | `Non_null_exp x -> non_null_expression env x
         )
       in
       let (op, is_logical, tok) =
         (match v2 with
          | `PLUSEQ tok -> G.Plus, false, JS.token env tok (* "+=" *)
          | `DASHEQ tok -> G.Minus, false, JS.token env tok (* "-=" *)
          | `STAREQ tok -> G.Mult, false, JS.token env tok (* "*=" *)
          | `SLASHEQ tok -> G.Div, false, JS.token env tok (* "/=" *)
          | `PERCEQ tok -> G.Mod, false, JS.token env tok (* "%=" *)
          | `HATEQ tok -> G.BitXor, false, JS.token env tok (* "^=" *)
          | `AMPEQ tok -> G.BitAnd, false, JS.token env tok (* "&=" *)
          | `BAREQ tok -> G.BitOr,false,  JS.token env tok (* "|=" *)
          | `GTGTEQ tok -> G.LSR, false, JS.token env tok (* ">>=" *)
          | `GTGTGTEQ tok -> G.ASR, false, JS.token env tok (* ">>>=" *)
          | `LTLTEQ tok -> G.LSL, false, JS.token env tok (* "<<=" *)
          | `STARSTAREQ tok -> G.Pow, false, JS.token env tok (* "**=" *)
          | `AMPAMPEQ tok -> G.And, true, JS.token env tok (* "&&=" *)
          | `BARBAREQ tok -> G.Or, true, JS.token env tok (* "||=" *)
          | `QMARKQMARKEQ tok -> G.Nullish, true, JS.token env tok (* "??=" *)
         )
       in
       let rhs = expression env v3 in
       (* less: should use intermediate instead of repeating v1 *)
       if is_logical then
         Apply (IdSpecial (ArithOp op, tok), fb [lhs; Assign (lhs, tok, rhs)])
       else
         Assign (lhs, tok, Apply (IdSpecial (ArithOp op, tok), fb [lhs; rhs]))

   | `Await_exp (v1, v2) ->
       let v1 = JS.token env v1 (* "await" *) in
       let v2 = expression env v2 in
       Apply (IdSpecial (Await, v1), fb [v2])
   | `Un_exp x -> unary_expression env x
   | `Bin_exp x -> binary_expression env x
   | `Tern_exp (v1, v2, v3, v4, v5) ->
       let v1 = expression env v1 in
       let _v2 = JS.token env v2 (* "?" *) in
       let v3 = expression env v3 in
       let _v4 = JS.token env v4 (* ":" *) in
       let v5 = expression env v5 in
       Conditional (v1, v3, v5)
   | `Update_exp x -> update_expression env x
   | `New_exp (v1, v2, v3, v4) ->
       let v1 = JS.token env v1 (* "new" *) in
       let v2 = primary_expression env v2 in
       (* TODO types *)
       let _v3 =
         match v3 with
         | Some x -> type_arguments env x |> PI.unbracket
         | None -> []
       in
       let t1, xs, t2 =
         (match v4 with
          | Some x -> arguments env x
          | None -> JS.fb [])
       in
       (* less: we should remove the extra Apply but that's what we do in pfff*)
       let newcall = Apply (IdSpecial (New, v1), fb [v2]) in
       Apply (newcall, (t1, xs, t2))
   | `Yield_exp (v1, v2) ->
       let v1 = JS.token env v1 (* "yield" *) in
       let v2 =
         (match v2 with
          | `STAR_exp (v1bis, v2) ->
              let _v1bis = JS.token env v1bis (* "*" *) in
              let v2 = expression env v2 in
              Apply (IdSpecial (YieldStar, v1), fb [v2])
          | `Opt_exp opt ->
              (match opt with
               | Some x ->
                   let x = expression env x in
                   Apply (IdSpecial (Yield, v1), fb [x])
               | None ->
                   Apply (IdSpecial (Yield, v1), fb [])
              )
         )
       in
       v2
  )

and anon_choice_paren_exp_9c42f0a (env : env) (x : CST.anon_choice_paren_exp_9c42f0a) =
  (match x with
   | `Paren_exp x -> parenthesized_expression env x
   | `Choice_choice_member_exp x -> lhs_expression env x
  )

and primary_type (env : env) (x : CST.primary_type) : type_ =
  (match x with
   | `Paren_type (v1, v2, v3) ->
       let _v1 = JS.token env v1 (* "(" *) in
       let v2 = type_ env v2 in
       let _v3 = JS.token env v3 (* ")" *) in
       v2
   | `Pred_type x ->
       let id = predefined_type env x in
       (* less: could also be a G.TyBuiltin *)
       TyName ([id])
   | `Id tok ->
       let id = JS.identifier env tok (* identifier *) in
       TyName ([id])
   | `Nested_type_id x ->
       let xs = nested_type_identifier env x in
       TyName (xs)
   | `Gene_type x ->
       TyName (generic_type env x)

   | `Obj_type x ->
       let (t1, xs, t2) = object_type env x in
       let _xs = xs |> Common.map_filter (function
         (* TODO *)
         | Left _fld -> None
         | Right _sts -> None
       ) in
       TyRecordAnon ((t1, (), t2))
   | `Array_type x ->
       (match x with
        | `Read_prim_type_LBRACK_RBRACK (v1, v2, v3, v4) ->
            let _v1 = JS.token env v1 (* "readonly" *) in (* TODO add to AST *)
            let v2 = primary_type env v2 in
            let v3 = JS.token env v3 (* "[" *) in
            let v4 = JS.token env v4 (* "]" *) in
            TyArray (v2, (v3, (), v4))
        | `Prim_type_LBRACK_RBRACK (v1, v2, v3) ->
            let v1 = primary_type env v1 in
            let v2 = JS.token env v2 (* "[" *) in
            let v3 = JS.token env v3 (* "]" *) in
            TyArray (v1, (v2, (), v3))
       )
   | `Tuple_type x ->
       (match x with
        | `Tuple_type_body x -> tuple_type_body env x
        | `Read_tuple_type_body (v1, v2) ->
            let _v1_TODO = JS.token env v1 (* "readonly" *) in
            let v2 = tuple_type_body env v2 in
            v2
       )
   | `Flow_maybe_type (v1, v2) ->
       let v1 = JS.token env v1 (* "?" *) in
       let v2 = primary_type env v2 in
       TyQuestion (v1, v2)
   | `Type_query x ->
       type_query env x

   | `Index_type_query (v1, v2) ->
       let v1 = JS.token env v1 (* "keyof" *) in
       let v2 =
         match v2 with
         | `Gene_type x -> TyName (generic_type env x)
         | `Id tok -> TyName [JS.identifier env tok] (* identifier *)
         | `Nested_type_id x -> TyName (nested_type_identifier env x)
         | `Type_query x -> type_query env x
       in
       TypeTodo (("KeyOf", v1), [Type v2])
   | `This tok ->
       let v1 = JS.token env tok in (* "this" *)
       TypeTodo (("This", v1), [])
   | `Exis_type tok ->
       let v1 = JS.token env tok (* "*" *) in
       TypeTodo (("*", v1), [])
   | `Lit_type x ->
       let v1 = literal_type env x in
       TypeTodo (("LitType", fake), [Expr (L v1);])
   | `Lookup_type (v1, v2, v3, v4) ->
       let v1 = primary_type env v1 in
       let v2 = JS.token env v2 (* "[" *) in
       let v3 = type_ env v3 in
       let _v4 = JS.token env v4 (* "]" *) in
       TypeTodo (("LookupType", v2), [Type v1; Type v3])
   | `Cond_type (v1, v2, v3, v4, v5, v6, v7) ->
       let v1 = type_ env v1 in
       let _v2 = JS.token env v2 (* "extends" *) in
       let v3 = type_ env v3 in
       let v4 = JS.token env v4 (* "?" *) in
       let v5 = type_ env v5 in
       let _v6 = JS.token env v6 (* ":" *) in
       let v7 = type_ env v7 in
       TypeTodo (("ConditionalType", v4),
                 [Type v1; Type v3; Type v5; Type v7])
  )

and index_signature (env : env) ((v1, v2, v3, v4, v5) : CST.index_signature) =
  let _v1 =
    match v1 with
    | Some (v1, v2) ->
        let v1 =
          match v1 with
          | Some tok -> Some (JS.token env tok) (* "-" *)
          | None -> None
        in
        let v2 = JS.token env v2 (* "readonly" *) in
        Some (v1, v2) (* TODO add to AST *)
    | None -> None
  in
  let v2 = JS.token env v2 (* "[" *) in
  let v3 =
    (match v3 with
     | `Choice_id_COLON_type (v2, v3, v4) ->
         let v2 = anon_choice_type_id_dd17e7d env v2 in
         let v3 = JS.token env v3 (* ":" *) in
         let v4 = type_ env v4 in
         TypeTodo (("IndexKey", v3), [Type (TyName [v2]); Type v4])
     | `Mapped_type_clause x -> mapped_type_clause env x
    )
  in
  let _v4 = JS.token env v4 (* "]" *) in
  let v5 =
    (match v5 with
     | `Type_anno x -> type_annotation env x |> snd
     | `Omit_type_anno (v1, v2) ->
         let _v1_TODO = JS.token env v1 (* "-?:" *) in
         let v2 = type_ env v2 in
         v2
     | `Opting_type_anno (v1, v2) ->
         let _v1_TODO = JS.token env v1 (* "?:" *) in
         let v2 = type_ env v2 in
         v2
    )
  in
  TypeTodo (("Indexsig", v2), [Type v3; Type v5])

and type_query (env : env) ((v1, v2) : CST.type_query) =
  let v1 = JS.token env v1 (* "typeof" *) in
  let v2 =
    (match v2 with
     | `Id tok ->
         JS.identifier env tok (* identifier *)
         |> idexp_or_special
     | `Nested_id x ->
         nested_identifier env x
         |> concat_nested_identifier
         |> idexp_or_special
     | `Gene_type x ->
         generic_type env x
         |> concat_nested_identifier
         |> idexp_or_special
     | `Call_exp x -> call_expression env x
    )
  in
  TypeTodo (("TypeQuery", v1), [Expr v2])

and unary_expression (env : env) (x : CST.unary_expression) =
  (match x with
   | `BANG_exp (v1, v2) ->
       let v1 = JS.token env v1 (* "!" *) in
       let v2 = expression env v2 in
       Apply (IdSpecial (ArithOp G.Not, v1), fb [v2])
   | `TILDE_exp (v1, v2) ->
       let v1 = JS.token env v1 (* "~" *) in
       let v2 = expression env v2 in
       Apply (IdSpecial (ArithOp G.BitNot, v1), fb [v2])
   | `DASH_exp (v1, v2) ->
       let v1 = JS.token env v1 (* "-" *) in
       let v2 = expression env v2 in
       Apply (IdSpecial (ArithOp G.Minus, v1), fb [v2])
   | `PLUS_exp (v1, v2) ->
       let v1 = JS.token env v1 (* "+" *) in
       let v2 = expression env v2 in
       Apply (IdSpecial (ArithOp G.Plus, v1), fb [v2])
   | `Typeof_exp (v1, v2) ->
       let v1 = JS.token env v1 (* "typeof" *) in
       let v2 = expression env v2 in
       Apply (IdSpecial (Typeof, v1), fb [v2])
   | `Void_exp (v1, v2) ->
       let v1 = JS.token env v1 (* "void" *) in
       let v2 = expression env v2 in
       Apply (IdSpecial (Void, v1), fb [v2])
   | `Delete_exp (v1, v2) ->
       let v1 = JS.token env v1 (* "delete" *) in
       let v2 = expression env v2 in
       Apply (IdSpecial (Delete, v1), fb [v2])
  )

and formal_parameters (env : env) ((v1, v2, v3) : CST.formal_parameters) : parameter list=
  let _v1 = JS.token env v1 (* "(" *) in
  let v2 =
    (match v2 with
     | Some (v1, v2, v3, v4) ->
         let v1 = List.map (decorator env) v1 in
         let v2 = anon_choice_requ_param_1bd7580 env v2 in
         let p = add_attributes_param v1 v2 in
         let ps =
           List.map (fun (v1, v2, v3) ->
             let _v1 = JS.token env v1 (* "," *) in
             let v2 = List.map (decorator env) v2 in
             let v3 = anon_choice_requ_param_1bd7580 env v3 in
             add_attributes_param v2 v3
           ) v3
         in
         let _v4 =
           (match v4 with
            | Some tok -> Some (JS.token env tok) (* "," *)
            | None -> None)
         in
         p :: ps
     | None -> [])
  in
  let _v3 = JS.token env v3 (* ")" *) in
  v2

(* class Component<Props = any, State = any> { ... *)
and default_type (env : env) ((v1, v2) : CST.default_type) =
  let _v1 = JS.token env v1 (* "=" *) in
  let v2 = type_ env v2 in
  v2

and switch_body (env : env) ((v1, v2, v3) : CST.switch_body) =
  let _v1 = JS.token env v1 (* "{" *) in
  let v2 =
    List.map (fun x ->
      (match x with
       | `Switch_case x -> switch_case env x
       | `Switch_defa x -> switch_default env x
      )
    ) v2
  in
  let _v3 = JS.token env v3 (* "}" *) in
  v2

and mapped_type_clause (env : env) ((v1, v2, v3) : CST.mapped_type_clause) =
  let v1 = JS.str env v1 (* identifier *) in
  let v2 = JS.token env v2 (* "in" *) in
  let v3 = type_ env v3 in
  TypeTodo (("MappedType", v2), [Expr (Id v1); Type v3])

and statement1 (env : env) (x : CST.statement) : stmt =
  statement env x |> stmt1

and statement (env : env) (x : CST.statement) : stmt list =
  (match x with
   | `Export_stmt x ->
       let xs = export_statement env x in
       xs
   | `Import_stmt (v1, v2, v3, v4) ->
       let v1 = JS.token env v1 (* "import" *) in
       let tok = v1 in
       let _v2 = (* 'type' or 'typeof' *)
         (match v2 with
          | Some x -> Some (anon_choice_type_2b11f6b env x)
          | None -> None)
       in
       let v3 =
         (match v3 with
          | `Import_clause_from_clause (v1, v2) ->
              let f = import_clause env v1 in
              let _t, path = JS.from_clause env v2 in
              f tok path
          | `Import_requ_clause x ->
              [import_require_clause v1 env x]
          | `Str x ->
              let file = JS.string_ env x in [ImportFile (tok, file)]
         )
       in
       let _v4 = JS.semicolon env v4 in
       v3 |> List.map (fun m -> M m)
   | `Debu_stmt (v1, v2) ->
       let v1 = JS.identifier env v1 (* "debugger" *) in
       let v2 = JS.semicolon env v2 in
       [ExprStmt (idexp v1, v2)]
   | `Exp_stmt x ->
       let (e, t) = expression_statement env x in
       [ExprStmt (e, t)]
   | `Decl x ->
       let vars = declaration env x in
       vars |> List.map (fun x -> DefStmt x)
   | `Stmt_blk x -> [statement_block env x]
   | `If_stmt (v1, v2, v3, v4) ->
       let v1 = JS.token env v1 (* "if" *) in
       let v2 = parenthesized_expression env v2 in
       let v3 = statement1 env v3 in
       let v4 =
         (match v4 with
          | Some (v1, v2) ->
              let _v1 = JS.token env v1 (* "else" *) in
              let v2 = statement1 env v2 in
              Some v2
          | None -> None)
       in
       [If (v1, v2, v3, v4)]
   | `Switch_stmt (v1, v2, v3) ->
       let v1 = JS.token env v1 (* "switch" *) in
       let v2 = parenthesized_expression env v2 in
       let v3 = switch_body env v3 in
       [Switch (v1, v2, v3)]
   | `For_stmt (v1, v2, v3, v4, v5, v6, v7) ->
       let v1 = JS.token env v1 (* "for" *) in
       let _v2 = JS.token env v2 (* "(" *) in
       let v3 =
         (match v3 with
          | `Lexi_decl x ->
              let vars = lexical_declaration env x in
              Left vars
          | `Var_decl x ->
              let vars = variable_declaration env x in
              Left vars
          | `Exp_stmt x ->
              let (e, _t) = expression_statement env x in
              Right e
          | `Empty_stmt tok ->
              let _x = JS.token env tok (* ";" *) in
              Left []
         )
       in
       let v4 =
         (match v4 with
          | `Exp_stmt x ->
              let (e, _t) = expression_statement env x in
              Some e
          | `Empty_stmt tok ->
              let _x = JS.token env tok (* ";" *) in
              None
         )
       in
       let v5 =
         (match v5 with
          | Some x -> Some (expressions env x)
          | None -> None)
       in
       let _v6 = JS.token env v6 (* ")" *) in
       let v7 = statement1 env v7 in
       [For (v1, ForClassic (v3, v4, v5), v7)]
   | `For_in_stmt (v1, v2, v3, v4) ->
       let v1 = JS.token env v1 (* "for" *) in
       let _v2TODO =
         (match v2 with
          | Some tok -> Some (JS.token env tok) (* "await" *)
          | None -> None)
       in
       let v3 = for_header env v3 in
       let v4 = statement1 env v4 in
       [For (v1, v3, v4)]
   | `While_stmt (v1, v2, v3) ->
       let v1 = JS.token env v1 (* "while" *) in
       let v2 = parenthesized_expression env v2 in
       let v3 = statement1 env v3 in
       [While (v1, v2, v3)]
   | `Do_stmt (v1, v2, v3, v4, v5) ->
       let v1 = JS.token env v1 (* "do" *) in
       let v2 = statement1 env v2 in
       let _v3 = JS.token env v3 (* "while" *) in
       let v4 = parenthesized_expression env v4 in
       let _v5 = JS.semicolon env v5 in
       [Do (v1, v2, v4)]
   | `Try_stmt (v1, v2, v3, v4) ->
       let v1 = JS.token env v1 (* "try" *) in
       let v2 = statement_block env v2 in
       let v3 =
         (match v3 with
          | Some x -> Some (catch_clause env x)
          | None -> None)
       in
       let v4 =
         (match v4 with
          | Some x -> Some (finally_clause env x)
          | None -> None)
       in
       [Try (v1, v2, v3, v4)]
   | `With_stmt (v1, v2, v3) ->
       let v1 = JS.token env v1 (* "with" *) in
       let v2 = parenthesized_expression env v2 in
       let v3 = statement1 env v3 in
       [With (v1, v2, v3)]
   | `Brk_stmt (v1, v2, v3) ->
       let v1 = JS.token env v1 (* "break" *) in
       let v2 =
         (match v2 with
          | Some tok -> Some (JS.identifier env tok) (* identifier *)
          | None -> None)
       in
       let v3 = JS.semicolon env v3 in
       [Break (v1, v2, v3)]
   | `Cont_stmt (v1, v2, v3) ->
       let v1 = JS.token env v1 (* "continue" *) in
       let v2 =
         (match v2 with
          | Some tok -> Some (JS.identifier env tok) (* identifier *)
          | None -> None)
       in
       let v3 = JS.semicolon env v3 in
       [Continue (v1, v2, v3)]
   | `Ret_stmt (v1, v2, v3) ->
       let v1 = JS.token env v1 (* "return" *) in
       let v2 =
         (match v2 with
          | Some x -> Some (expressions env x)
          | None -> None)
       in
       let v3 = JS.semicolon env v3 in
       [Return (v1, v2, v3)]
   | `Throw_stmt (v1, v2, v3) ->
       let v1 = JS.token env v1 (* "throw" *) in
       let v2 = expressions env v2 in
       let v3 = JS.semicolon env v3 in
       [Throw (v1, v2, v3)]
   | `Empty_stmt tok ->
       [JS.empty_stmt env tok (* ";" *)]
   | `Labe_stmt (v1, v2, v3) ->
       let v1 = anon_choice_type_id_dd17e7d env v1 in
       let _v2 = JS.token env v2 (* ":" *) in
       let v3 = statement1 env v3 in
       [Label (v1, v3)]
  )

and method_definition (env : env) ((v1, v2, v3, v4, v5, v6, v7, v8, v9) : CST.method_definition) : property =
  let v1 =
    (match v1 with
     | Some x -> [accessibility_modifier env x]
     | None -> [])
  in
  let v2 =
    (match v2 with
     | Some tok -> [(Static, JS.token env tok)] (* "static" *)
     | None -> [])
  in
  let v3 =
    (match v3 with
     | Some tok -> [Readonly, JS.token env tok] (* "readonly" *)
     | None -> [])
  in
  let v4 =
    (match v4 with
     | Some tok -> [Async, JS.token env tok] (* "async" *)
     | None -> [])
  in
  let v5 =
    (match v5 with
     | Some x -> [anon_choice_get_8fb02de env x]
     | None -> [])
  in
  let v6 = property_name env v6 in
  let v7 =
    (match v7 with (* indicates optional method? *)
     | Some tok -> [Optional, JS.token env tok] (* "?" *)
     | None -> [])
  in
  let (_tparams, (v8, tret)) = call_signature env v8 in
  let v9 = statement_block env v9 in
  let attrs = (v1 @ v2 @ v3 @ v4 @ v5 @ v7) |> List.map attr in
  let f = { f_attrs = []; f_params = v8; f_body = v9; f_rettype = tret } in
  let e = Fun (f, None) in
  let ty = None in
  Field {fld_name = v6; fld_attrs = attrs; fld_type = ty; fld_body = Some e }

and class_declaration (env : env) ((v1, v2, v3, v4, v5, v6, v7) : CST.class_declaration) : definition =
  let v1 = List.map (decorator env) v1 in
  let v2 = JS.token env v2 (* "class" *) in
  let v3 = JS.identifier env v3 (* identifier *) in
  (* TODO types: type_parameters *)
  let _v4 =
    (match v4 with
     | Some x -> type_parameters env x
     | None -> [])
  in
  let c_extends, c_implements =
    (match v5 with
     | Some x -> class_heritage env x
     | None -> [], [])
  in
  let v6 = class_body env v6 in
  let _v7 =
    (match v7 with
     | Some tok -> Some (JS.token env tok) (* automatic_semicolon *)
     | None -> None)
  in
  let c = { c_kind = G.Class, v2; c_extends; c_implements;
            c_body = v6; c_attrs = v1 } in
  basic_entity v3, ClassDef c

and array_ (env : env) ((v1, v2, v3) : CST.array_) =
  let v1 = JS.token env v1 (* "[" *) in
  let v2 =
    anon_opt_opt_choice_exp_rep_COMMA_opt_choice_exp_208ebb4 env v2
  in
  let v3 = JS.token env v3 (* "]" *) in
  Arr (v1, v2, v3)

and export_statement (env : env) (x : CST.export_statement) : stmt list =
  (match x with
   | `Choice_export_choice_STAR_from_clause_choice_auto_semi x ->
       (match x with
        | `Export_choice_STAR_from_clause_choice_auto_semi (v1, v2) ->
            let tok = JS.token env v1 (* "export" *) in
            let v2 =
              (match v2 with
               | `STAR_from_clause_choice_auto_semi (v1, v2, v3) ->
                   let v1 = JS.token env v1 (* "*" *) in
                   let tok2, path = JS.from_clause env v2 in
                   let _v3 = JS.semicolon env v3 in
                   [M (ReExportNamespace (tok, v1, tok2, path))]
               | `Export_clause_from_clause_choice_auto_semi (v1, v2, v3) ->
                   let v1 = export_clause env v1 in
                   let (tok2, path) = JS.from_clause env v2 in
                   let _v3 = JS.semicolon env v3 in
                   v1 |> List.map (fun (n1, n2opt) ->
                     let tmpname = "!tmp_" ^ fst n1, snd n1 in
                     let import = Import (tok2, n1, Some tmpname, path) in
                     let e = idexp tmpname in
                     match n2opt with
                     | None ->
                         let v = Ast_js.mk_const_var n1 e in
                         [M import; DefStmt v; M (Export (tok, n1))]
                     | Some (n2) ->
                         let v = Ast_js.mk_const_var n2 e in
                         [M import; DefStmt v; M (Export (tok, n2))]
                   ) |> List.flatten
               | `Export_clause_choice_auto_semi (v1, v2) ->
                   let v1 = export_clause env v1 in
                   let _v2 = JS.semicolon env v2 in
                   v1 |> List.map (fun (n1, n2opt) ->
                     (match n2opt with
                      | None -> [M (Export (tok, n1))]
                      | Some n2 ->
                          let v = Ast_js.mk_const_var n2 (idexp n1) in
                          [DefStmt v; M (Export (tok, n2))]
                     )
                   ) |> List.flatten
              )
            in
            v2
        | `Rep_deco_export_choice_decl (v1, v2, v3) ->
            let v1 = List.map (decorator env) v1 in
            let tok = JS.token env v2 (* "export" *) in
            let v3 =
              (match v3 with
               | `Decl x ->
                   let defs = declaration env x in
                   defs |> List.map (fun def ->
                     let (ent, defkind) = def in
                     let n = ent.name in
                     let ent = { ent with attrs = ent.attrs @ v1 } in
                     [DefStmt (ent, defkind); M (Export (tok, n))]
                   ) |> List.flatten
               | `Defa_exp_choice_auto_semi (v1, v2, v3) ->
                   let v1 = JS.token env v1 (* "default" *) in
                   let v2 = expression env v2 in
                   let _v3 = JS.semicolon env v3 in
                   let def, n = Ast_js.mk_default_entity_def v1 v2 in
                   [DefStmt def; M (Export (v1, n))]
              )
            in
            v3
       )
   | `Export_EQ_id_choice_auto_semi (v1, v2, v3, v4) ->
       let _v1 = JS.token env v1 (* "export" *) in
       let _v2 = JS.token env v2 (* "=" *) in
       let _v3 = JS.token env v3 (* identifier *) in
       let _v4 = JS.semicolon env v4 in
       (* TODO 'export = ZipCodeValidator;' *)
       []

   | `Export_as_name_id_choice_auto_semi (v1, v2, v3, v4, v5) ->
       let _v1 = JS.token env v1 (* "export" *) in
       let _v2 = JS.token env v2 (* "as" *) in
       let _v3 = JS.token env v3 (* "namespace" *) in
       let _v4 = JS.token env v4 (* identifier *) in
       let _v5 = JS.semicolon env v5 in
       (* TODO 'export as namespace mathLib;' *)
       []

   | `Export_opt_defa_func_sign (v1, v2, v3) ->
       let _v1 = JS.token env v1 (* "export" *) in
       let _v2 =
         match v2 with
         | None -> None
         | Some x -> Some (JS.token env x) (* "default" *)
       in
       let _v3 () = todo_function_signature env v3 in
       (* TODO 'export default function foo(): number;' *)
       []
  )

and type_annotation (env : env) ((v1, v2) : CST.type_annotation) =
  let v1 = JS.token env v1 (* ":" *) in
  let v2 = type_ env v2 in
  v1, v2

and anon_rep_COMMA_opt_choice_exp_ca698a5 (env : env) (xs : CST.anon_rep_COMMA_opt_choice_exp_ca698a5) =
  List.filter_map (fun (v1, v2) ->
    let _v1 = JS.token env v1 (* "," *) in
    let v2 =
      (match v2 with
       | Some x -> Some (anon_choice_exp_9818c1b env x)
       | None -> None)
    in
    v2
  ) xs

and decorator_call_expression (env : env) ((v1, v2) : CST.decorator_call_expression) =
  let v1 = anon_choice_type_id_b8f8ced env v1 in
  let v2 = arguments env v2 in
  v1, v2

and update_expression (env : env) (x : CST.update_expression) =
  (match x with
   | `Exp_choice_PLUSPLUS (v1, v2) ->
       let v1 = expression env v1 in
       let op, t = anon_choice_PLUSPLUS_e498e28 env v2 in
       Apply (IdSpecial (IncrDecr (op, G.Postfix), t), fb [v1])
   | `Choice_PLUSPLUS_exp (v1, v2) ->
       let op, t = anon_choice_PLUSPLUS_e498e28 env v1 in
       let v2 = expression env v2 in
       Apply (IdSpecial (IncrDecr (op, G.Prefix), t), fb [v2])
  )

and anon_choice_export_stmt_f90d83f (env : env) (x : CST.anon_choice_export_stmt_f90d83f) =
  (match x with
   | `Export_stmt x ->
       let xs = export_statement env x in
       Right xs
   | `Prop_sign (v1, v2, v3, v4, v5, v6) ->
       let v1 =
         (match v1 with
          | Some x -> [accessibility_modifier env x]
          | None -> [])
       in
       let v2 =
         (match v2 with
          | Some tok -> [Static, JS.token env tok] (* "static" *)
          | None -> [])
       in
       let v3 =
         (match v3 with
          | Some tok -> [Readonly, JS.token env tok] (* "readonly" *)
          | None -> [])
       in
       let v4 = property_name env v4 in
       let v5 =
         (match v5 with
          | Some tok -> [Optional, JS.token env tok] (* "?" *)
          | None -> [])
       in
       let v6 =
         (match v6 with
          | Some x -> Some (type_annotation env x |> snd)
          | None -> None)
       in
       let attrs = (v1 @ v2 @ v3 @ v5) |> List.map attr in
       let fld =
         { fld_name = v4; fld_attrs = attrs; fld_type = v6; fld_body = None } in
       Left (Field fld)
   | `Call_sign_ x ->
       let (_tparams, x) = call_signature env x in
       let ty = mk_functype x in
       let name = PN ("CTOR??TODO", fake) in
       let fld =
         { fld_name = name; fld_attrs = []; fld_type = Some ty; fld_body = None}
       in
       Left (Field fld)
   | `Cons_sign (v1, v2, v3, v4) ->
       let v1 = JS.token env v1 (* "new" *) in
       let _tparams =
         (match v2 with
          | Some x -> type_parameters env x
          | None -> [])
       in
       let v3 = formal_parameters env v3 in
       let v4 =
         (match v4 with
          | Some x -> Some (type_annotation env x |> snd)
          | None -> None)
       in
       let ty = mk_functype (v3, v4) in
       let name = PN ("new", v1) in
       let fld =
         { fld_name = name; fld_attrs = []; fld_type = Some ty; fld_body = None}
       in
       Left (Field fld)
   | `Index_sign x ->
       let ty = index_signature env x in
       let name = PN ("IndexMethod??TODO?", fake) in
       let fld =
         { fld_name = name; fld_attrs = []; fld_type = Some ty; fld_body = None}
       in
       Left (Field fld)
   | `Meth_sign x ->
       let x = method_signature env x in
       Left (Field x)
  )

and public_field_definition (env : env) ((v1, v2, v3, v4, v5, v6) : CST.public_field_definition) =
  let _v1 =
    (match v1 with
     | Some x -> [accessibility_modifier env x]
     | None -> [])
  in
  let v2 =
    (match v2 with
     | `Opt_static_opt_read (v1, v2) ->
         let v1 =
           (match v1 with
            | Some tok -> [Static, JS.token env tok] (* "static" *)
            | None -> [])
         in
         let v2 =
           (match v2 with
            | Some tok -> [Readonly, JS.token env tok] (* "readonly" *)
            | None -> [])
         in
         v1 @ v2
     | `Opt_abst_opt_read (v1, v2)
     | `Opt_read_opt_abst (v2, v1) ->
         let v1 =
           (match v1 with
            | Some tok -> [Abstract, JS.token env tok] (* "abstract" *)
            | None -> [])
         in
         let v2 =
           (match v2 with
            | Some tok -> [Readonly, JS.token env tok] (* "readonly" *)
            | None -> [])
         in
         v1 @ v2
    )
  in
  let v3 = property_name env v3 in
  let _v4 =
    (match v4 with
     | Some x ->
         (match x with
          | `QMARK tok -> [Optional, JS.token env tok] (* "?" *)
          | `BANG tok -> [NotNull, JS.token env tok] (* "!" *)
         )
     | None -> [])
  in
  let v5 =
    (match v5 with
     | Some x -> Some (type_annotation env x |> snd)
     | None -> None)
  in
  let v6 =
    (match v6 with
     | Some x -> Some (initializer_ env x)
     | None -> None)
  in
  let attrs = v2 |> List.map attr in
  Field {fld_name = v3; fld_attrs = attrs; fld_type = v5; fld_body = v6 }

and anon_choice_choice_type_id_e16f95c (env : env) (x : CST.anon_choice_choice_type_id_e16f95c): parent =
  (match x with
   | `Choice_id x -> (* type to be extended *)
       Right (anon_choice_type_id_a85f573 env x)
   | `Exp x -> (* class expression to be extended *)
       Left (expression env x)
  )

and lexical_declaration (env : env) ((v1, v2, v3, v4) : CST.lexical_declaration) : var list =
  let v1 =
    (match v1 with
     | `Let tok -> Let, JS.token env tok (* "let" *)
     | `Const tok -> Const, JS.token env tok (* "const" *)
    )
  in
  let v2 = variable_declarator env v2 in
  let v3 =
    List.map (fun (v1, v2) ->
      let _v1 = JS.token env v1 (* "," *) in
      let v2 = variable_declarator env v2 in
      v2
    ) v3
  in
  let _v4 = JS.semicolon env v4 in
  build_vars v1 (v2::v3)

and extends_clause (env : env) ((v1, v2, v3) : CST.extends_clause)
  : parent list =
  let _v1 = JS.token env v1 (* "extends" *) in
  let v2 = anon_choice_choice_type_id_e16f95c env v2 in
  let v3 =
    List.map (fun (v1, v2) ->
      let _v1 = JS.token env v1 (* "," *) in
      let v2 = anon_choice_choice_type_id_e16f95c env v2 in
      v2
    ) v3
  in
  v2::v3

(* This function is similar to 'formal_parameter' in the js grammar. *)
and anon_choice_requ_param_1bd7580 (env : env) (x : CST.anon_choice_requ_param_1bd7580) : parameter =
  (match x with
   | `Requ_param (v1, v2, v3) ->
       let v1 = parameter_name env v1 in
       let v2 =
         (match v2 with
          | Some x -> Some (type_annotation env x |> snd)
          | None -> None)
       in
       let v3 =
         (match v3 with
          | Some x -> Some (initializer_ env x)
          | None -> None)
       in
       (match v1 with
        | Left id -> ParamClassic
                       { p_name = id; p_default = v3; p_type = v2; p_dots = None;
                         p_attrs = [] }
        (* TODO: can have types and defaults on patterns? *)
        | Right pat -> ParamPattern pat
       )

   | `Rest_param ((v1, v2), v3) ->
       let v1 = JS.token env v1 (* "..." *) in
       let id = JS.identifier env v2 (* identifier *) in
       let v3 =
         (match v3 with
          | Some x -> Some (type_annotation env x |> snd)
          | None -> None)
       in
       ParamClassic { p_name = id; p_default = None; p_type = v3;
                      p_dots = Some v1; p_attrs = [] }

   | `Opt_param (v1, v2, v3, v4) ->
       let v1 = parameter_name env v1 in
       let _v2TODO = JS.token env v2 (* "?" *) in
       let _v3 =
         (match v3 with
          | Some x -> Some (type_annotation env x)
          | None -> None)
       in
       let _v4 =
         (match v4 with
          | Some x -> Some (initializer_ env x)
          | None -> None)
       in
       (match v1 with
        | Left id -> ParamClassic (mk_param id)
        (* TODO: can have types and defaults on patterns? *)
        | Right pat -> ParamPattern pat
       )
  )

and enum_body (env : env) ((v1, v2, v3) : CST.enum_body) =
  let v1 = JS.token env v1 (* "{" *) in
  let v2 =
    (match v2 with
     | Some (v1, v2, v3) ->
         let v1 = anon_choice_prop_name_6cc9e4b env v1 in
         let v2 =
           List.map (fun (v1, v2) ->
             let _v1 = JS.token env v1 (* "," *) in
             let v2 = anon_choice_prop_name_6cc9e4b env v2 in
             v2
           ) v2
         in
         let _v3 =
           (match v3 with
            | Some tok -> Some (JS.token env tok) (* "," *)
            | None -> None)
         in
         v1::v2
     | None -> [])
  in
  let v3 = JS.token env v3 (* "}" *) in
  v1, v2, v3

and class_heritage (env : env) (x : CST.class_heritage)
  : parent list * type_ list =
  (match x with
   | `Extends_clause_opt_imples_clause (v1, v2) ->
       let v1 = extends_clause env v1 in
       let v2 =
         (match v2 with
          | Some x -> (implements_clause env x)
          | None -> [])
       in
       v1, v2
   | `Imples_clause x ->
       let x = implements_clause env x in
       [], x
  )

and property_name (env : env) (x : CST.property_name) =
  (match x with
   | `Choice_id x ->
       let id = anon_choice_type_id_dd17e7d env x in
       PN id
   | `Str x ->
       let s = JS.string_ env x in
       PN s
   | `Num tok ->
       let n = JS.number_as_string env tok (* number *) in
       PN n
   | `Comp_prop_name (v1, v2, v3) ->
       let _v1 = JS.token env v1 (* "[" *) in
       let v2 = expression env v2 in
       let _v3 = JS.token env v3 (* "]" *) in
       PN_Computed v2
  )

and switch_case (env : env) ((v1, v2, v3, v4) : CST.switch_case) =
  let v1 = JS.token env v1 (* "case" *) in
  let v2 = expressions env v2 in
  let _v3 = JS.token env v3 (* ":" *) in
  let v4 = List.map (statement env) v4 |> List.flatten in
  Case (v1, v2, stmt1 v4)

and spread_element (env : env) ((v1, v2) : CST.spread_element) =
  let v1 = JS.token env v1 (* "..." *) in
  let v2 = expression env v2 in
  v1, v2

and expressions (env : env) (x : CST.expressions) : expr =
  (match x with
   | `Exp x -> expression env x
   | `Seq_exp x -> sequence_expression env x
  )

and abstract_method_signature (env : env) ((v1, v2, v3, v4, v5, v6) : CST.abstract_method_signature) =
  let v1 =
    (match v1 with
     | Some x -> [accessibility_modifier env x]
     | None -> [])
  in
  let v2 = [Abstract, JS.token env v2] (* "abstract" *) in
  let v3 =
    (match v3 with
     | Some x -> [anon_choice_get_8fb02de env x]
     | None -> [])
  in
  let v4 = property_name env v4 in
  let v5 =
    (match v5 with
     | Some tok -> [Optional, JS.token env tok] (* "?" *)
     | None -> [])
  in
  let attrs = (v1 @ v2 @ v3 @ v5) |> List.map attr in
  let (_tparams, x) = call_signature env v6 in
  let t = mk_functype x in
  { fld_name = v4; fld_attrs = attrs; fld_type = Some t; fld_body = None }

and finally_clause (env : env) ((v1, v2) : CST.finally_clause) =
  let v1 = JS.token env v1 (* "finally" *) in
  let v2 = statement_block env v2 in
  v1, v2

and todo_asserts (env : env) ((v1, v2, v3, v4) : CST.asserts) =
  let v1 = JS.token env v1 (* ":" *) in
  let v2 = JS.token env v2 (* "asserts" *) in
  let v3 =
    (match v3 with
     | `Id tok ->
         let id = JS.identifier env tok (* identifier *) in
         idexp_or_special id
     | `This tok -> JS.this env tok (* "this" *)
    )
  in
  let v4 =
    (match v4 with
     | Some (v1, v2) ->
         let v1 = JS.token env v1 (* "is" *) in
         let v2 = type_ env v2 in
         todo env (v1, v2)
     | None -> todo env ())
  in
  todo env (v1, v2, v3, v4)

and call_signature (env : env) ((v1, v2, v3) : CST.call_signature)
  : type_parameter list * (parameter list * type_ option) =
  let v1 =
    (match v1 with
     | Some x -> type_parameters env x
     | None -> [])
  in
  let v2 = formal_parameters env v2 in
  let v3 =
    (match v3 with
     | Some x ->
         (match x with
          | `Type_anno x -> Some (type_annotation env x |> snd)
          | `Asserts x ->
              let _x () = todo_asserts env x in (* TODO *)
              None
          | `Type_pred_anno (v1, v2) ->
              let _v1 = JS.token env v1 (* ":" *) in
              let v2 =
                let v1, v2, v3 = v2 in
                let v1 =
                  match v1 with
                  | `Id tok ->
                      let id = JS.identifier env tok (* identifier *) in
                      idexp_or_special id
                  | `This tok -> JS.this env tok (* "this" *)
                in
                let v2 = JS.token env v2 (* "is" *) in
                let v3 = type_ env v3 in
                TypeTodo (("IsType", v2), [Expr v1; Type v3])
              in
              Some v2
         )
     | None -> None)
  in
  v1, (v2, v3)

and object_ (env : env) ((v1, v2, v3) : CST.object_) : obj_ =
  let v1 = JS.token env v1 (* "{" *) in
  let v2 =
    (match v2 with
     | Some (v1, v2) ->
         let v1 =
           (match v1 with
            | Some x -> [anon_choice_pair_bc93fa1 env x]
            | None -> [])
         in
         let v2 =
           List.filter_map (fun (v1, v2) ->
             let _v1 = JS.token env v1 (* "," *) in
             let v2 =
               (match v2 with
                | Some x -> Some (anon_choice_pair_bc93fa1 env x)
                | None -> None)
             in
             v2
           ) v2
         in
         v1 @ v2
     | None -> [])
  in
  let v3 = JS.token env v3 (* "}" *) in
  v1, v2, v3

and type_ (env : env) (x : CST.type_) : type_ =
  (match x with
   | `Prim_type x -> primary_type env x
   | `Union_type (v1, v2, v3) ->
       let v2 = JS.token env v2 (* "|" *) in
       let v3 = type_ env v3 in
       (match v1 with
        | Some x ->
            let x = type_ env x in
            TyOr (x, v2, v3)
        | None -> v3) (* ?? *)

   | `Inte_type (v1, v2, v3) ->
       let v2 = JS.token env v2 (* "&" *) in
       let v3 = type_ env v3 in
       (match v1 with
        | Some x ->
            let x = type_ env x in
            TyAnd (x, v2, v3)
        | None -> v3) (* ?? *)
   | `Func_type (v1, v2, v3, v4) ->
       let _tparams =
         (match v1 with
          | Some x -> type_parameters env x
          | None -> [])
       in
       let v2 = formal_parameters env v2 in
       let _v3 = JS.token env v3 (* "=>" *) in
       let v4 = type_ env v4 in
       mk_functype (v2, Some v4)
   | `Cons_type (v1, v2, v3, v4, v5) ->
       let v1 = JS.token env v1 (* "new" *) in
       let _tparams =
         (match v2 with
          | Some x -> type_parameters env x
          | None -> [])
       in
       let v3 = formal_parameters env v3 in
       let _v4 = JS.token env v4 (* "=>" *) in
       let v5 = type_ env v5 in
       let ty = mk_functype (v3, Some v5) in
       TypeTodo (("New", v1), [Type ty])
   | `Infer_type (v1, v2) ->
       let v1 = JS.token env v1 (* "infer" *) in
       let v2 = JS.identifier env v2 (* identifier *) in
       TypeTodo (("Infer", v1), [Type (TyName [v2])])
  )

and type_parameters (env : env) ((v1, v2, v3, v4, v5) : CST.type_parameters) : type_parameter list =
  let _v1 = JS.token env v1 (* "<" *) in
  let v2 = type_parameter env v2 in
  let v3 =
    List.map (fun (v1, v2) ->
      let _v1 = JS.token env v1 (* "," *) in
      let v2 = type_parameter env v2 in
      v2
    ) v3
  in
  let _v4 =
    (match v4 with
     | Some tok -> Some (JS.token env tok) (* "," *)
     | None -> None)
  in
  let _v5 = JS.token env v5 (* ">" *) in
  v2::v3

and constraint_ (env : env) ((v1, v2) : CST.constraint_) : type_parameter_constraint =
  let _v1 =
    (match v1 with
     | `Extends tok -> JS.token env tok (* "extends" *)
     | `COLON tok -> JS.token env tok (* ":" *)
    )
  in
  let v2 = type_ env v2 in
  v2

and parameter_name (env : env) ((v1, v2, v3) : CST.parameter_name) : (ident, pattern) Common.either =
  let _v1 =
    (match v1 with
     | Some x -> [accessibility_modifier env x]
     | None -> [])
  in
  let _v2 =
    (match v2 with
     | Some tok -> [JS.token env tok] (* "readonly" *)
     | None -> [])
  in
  let v3 =
    (match v3 with
     | `Id tok ->
         let id = JS.identifier env tok (* identifier *) in
         Left id
     | `Choice_decl x ->
         let id = reserved_identifier env x in
         Left id
     | `Choice_obj x ->
         let pat = destructuring_pattern env x in
         Right pat
     | `This tok ->
         (* treating 'this' as a regular identifier for now *)
         let id = JS.identifier env tok (* "this" *) in
         Left id
    )
  in
  v3

and lhs_expression (env : env) (x : CST.lhs_expression) =
  (match x with
   | `Choice_member_exp x ->
       (match x with
        | `Member_exp x -> member_expression env x
        | `Subs_exp x -> subscript_expression env x
        | `Id tok -> JS.identifier env tok |> idexp (* identifier *)
        | `Choice_decl x -> reserved_identifier env x |> idexp
        | `Choice_obj x -> destructuring_pattern env x
       )
   | `Non_null_exp x -> non_null_expression env x
  )

and statement_block (env : env) ((v1, v2, v3, v4) : CST.statement_block) =
  let v1 = JS.token env v1 (* "{" *) in
  let v2 = List.map (statement env) v2 |> List.flatten in
  let v3 = JS.token env v3 (* "}" *) in
  let _v4 =
    (match v4 with
     | Some tok -> Some (automatic_semicolon env tok) (* automatic_semicolon *)
     | None -> None)
  in
  Block (v1, v2, v3)

and function_declaration (env : env) ((v1, v2, v3, v4, v5, v6) : CST.function_declaration) : definition =
  let v1 =
    (match v1 with
     | Some tok -> [attr (Async, JS.token env tok)] (* "async" *)
     | None -> [])
  in
  let _v2 = JS.token env v2 (* "function" *) in
  let v3 = JS.identifier env v3 (* identifier *) in
  let (_tparams, (v4, tret)) = call_signature env v4 in
  let v5 = statement_block env v5 in
  let _v6 =
    (match v6 with
     | Some tok -> Some (JS.token env tok) (* automatic_semicolon *)
     | None -> None)
  in
  let f = { f_attrs = v1; f_params = v4; f_body = v5; f_rettype = tret } in
  basic_entity v3, FuncDef f

and todo_function_signature (env : env) ((v1, v2, v3, v4, v5) : CST.function_signature) =
  let v1 =
    (match v1 with
     | Some tok -> JS.token env tok (* "async" *)
     | None -> todo env ())
  in
  let v2 = JS.token env v2 (* "function" *) in
  let v3 = JS.token env v3 (* identifier *) in
  let v4 = call_signature env v4 in
  let v5 =
    (match v5 with
     | `Choice_auto_semi x -> JS.semicolon env x
     | `Func_sign_auto_semi tok ->
         JS.token env tok (* function_signature_automatic_semicolon *)
    )
  in
  todo env (v1, v2, v3, v4, v5)

and anon_choice_type_id_a85f573 (env : env) (x : CST.anon_choice_type_id_a85f573) : type_ =
  (match x with
   | `Id tok -> TyName [JS.str env tok] (* identifier *)
   | `Nested_type_id x ->
       TyName (nested_type_identifier env x)
   | `Gene_type x ->
       TyName (generic_type env x)
  )

and template_substitution (env : env) ((v1, v2, v3) : CST.template_substitution) =
  let _v1 = JS.token env v1 (* "${" *) in
  let v2 = expressions env v2 in
  let _v3 = JS.token env v3 (* "}" *) in
  v2

and tuple_type_body (env : env) ((v1, v2, v3) : CST.tuple_type_body) =
  let v1 = JS.token env v1 (* "[" *) in
  let v2 =
    (match v2 with
     | Some (v1, v2) ->
         let v1 = tuple_type_member env v1 in
         let v2 =
           List.map (fun (v1, v2) ->
             let _v1 = JS.token env v1 (* "," *) in
             let v2 = tuple_type_member env v2 in
             v2
           ) v2
         in
         v1 :: v2
     | None -> [])
  in
  let v3 = JS.token env v3 (* "]" *) in
  TyTuple (v1, v2, v3)

and tuple_type_member (env : env) (x : CST.tuple_type_member) =
  (match x with
   | `Labe_tuple_type_member (v1, v2) ->
       let _v1_TODO = tuple_type_identifier env v1 in
       let v2 = type_annotation env v2 |> snd in
       TyTupMember v2
   | `Opt_type (v1, v2) ->
       let v1 = type_ env v1 in
       let v2 = JS.token env v2 (* "?" *) in
       TyTupOpt (v1, v2)
   | `Rest_type (v1, v2) ->
       let v1 = JS.token env v1 (* "..." *) in
       let v2 = type_ env v2 in
       TyTupRest (v1, v2)
   | `Type x ->
       TyTupMember (type_ env x)
  )

and method_signature (env : env) ((v1, v2, v3, v4, v5, v6, v7, v8) : CST.method_signature) =
  let v1 =
    (match v1 with
     | Some x -> [accessibility_modifier env x]
     | None -> [])
  in
  let v2 =
    (match v2 with
     | Some tok -> [Static, JS.token env tok] (* "static" *)
     | None -> [])
  in
  let v3 =
    (match v3 with
     | Some tok -> [Readonly, JS.token env tok] (* "readonly" *)
     | None -> [])
  in
  let v4 =
    (match v4 with
     | Some tok -> [Async, JS.token env tok] (* "async" *)
     | None -> [])
  in
  let v5 =
    (match v5 with
     | Some x -> [anon_choice_get_8fb02de env x]
     | None -> [])
  in
  let v6 = property_name env v6 in
  let v7 =
    (match v7 with
     | Some tok -> [Optional, JS.token env tok] (* "?" *)
     | None -> [])
  in
  let attrs = (v1 @ v2 @ v3 @ v4 @ v5 @ v7) |> List.map attr in
  let (_tparams, x) = call_signature env v8 in
  let t = mk_functype x in
  { fld_name = v6; fld_attrs = attrs; fld_type = Some t; fld_body = None}

(* TODO: types *)
(* This covers mostly type definitions but includes also javascript constructs
   like function parameters, so it will be called even if we ignore types. *)
and declaration (env : env) (x : CST.declaration) : definition list =
  (match x with
   | `Choice_func_decl x ->
       (match x with
        | `Func_decl x -> [function_declaration env x]
        | `Gene_func_decl x -> [generator_function_declaration env x]
        | `Class_decl x -> [class_declaration env x]
        | `Lexi_decl x -> lexical_declaration env x |> vars_to_defs
        | `Var_decl x -> variable_declaration env x |> vars_to_defs
       )
   | `Func_sign (v1, v2, v3, v4, v5) ->
       let _v1 =
         (match v1 with
          | Some tok -> [Async, JS.token env tok] (* "async" *)
          | None -> [])
       in
       let v2 = JS.token env v2 (* "function" *) in
       let v3 = JS.identifier env v3 (* identifier *) in
       let (_tparams, x) = call_signature env v4 in
       let ty = mk_functype x in
       let _v5 =
         match v5 with
         | `Choice_auto_semi x -> JS.semicolon env x
         | `Func_sign_auto_semi tok -> JS.token env tok
       in
       [basic_entity v3, (* DefTodo? *)
        VarDef { v_kind = Const, v2; v_init = None; v_type = Some ty; }]
   | `Abst_class_decl (v1, v2, v3, v4, v5, v6, v7) ->
       let _v1_TODO = List.map (decorator env) v1 in
       let v2 = attr (Abstract, JS.token env v2) (* "abstract" *) in
       let v3 = JS.token env v3 (* "class" *) in
       let v4 = JS.identifier env v4 (* identifier *) in
       let _tparams =
         (match v5 with
          | Some x -> type_parameters env x
          | None -> [])
       in
       let c_extends, c_implements =
         (match v6 with
          | Some x -> class_heritage env x
          | None -> [], [])
       in
       let v7 = class_body env v7 in
       let attrs = [v2] in
       let c = { c_kind = G.Class, v3; c_extends; c_implements;
                 c_body = v7; c_attrs = attrs } in
       [basic_entity v4, ClassDef c]

   | `Module (v1, v2) ->
       (* does this exist only in .d.ts files? *)
       let _v1 = JS.token env v1 (* "module" *) in
       let _id, _opt_body = module__ env v2 in
       [] (* TODO *)

   | `Inte_module x ->
       (* namespace *)
       let _x = internal_module env x in
       [] (* TODO *)

   | `Type_alias_decl (v1, v2, v3, v4, v5, v6) ->
       let _v1 = JS.token env v1 (* "type" *) in
       let _v2 = JS.token env v2 (* identifier *) in
       let _v3 =
         (match v3 with
          | Some x -> type_parameters env x
          | None -> [])
       in
       let _v4 = JS.token env v4 (* "=" *) in
       let _v5 = type_ env v5 in
       let _v6 = JS.semicolon env v6 in
       [] (* TODO *)

   | `Enum_decl (v1, v2, v3, v4) ->
       let _v1 =
         (match v1 with
          | Some tok -> [JS.token env tok] (* "const" *)
          | None -> [])
       in
       let _v2 = JS.token env v2 (* "enum" *) in
       let _v3 = JS.identifier env v3 (* identifier *) in
       let _v4 = enum_body env v4 in
       [] (* TODO *)

   | `Inte_decl (v1, v2, v3, v4, v5) ->
       let v1 = JS.token env v1 (* "interface" *) in
       let v2 = JS.identifier env v2 (* identifier *) in
       let _v3 =
         (match v3 with
          | Some x -> type_parameters env x
          | None -> [])
       in
       let v4 =
         (match v4 with
          | Some x -> (extends_clause env x)
          | None -> [])
       in
       let (t1, xs, t2) = object_type env v5 in
       let xs = xs |> Common.map_filter (function
         (* TODO *)
         | Left _fld -> None
         | Right _sts -> None
       )
       in
       let c = { c_kind = G.Interface, v1;
                 c_extends = v4; c_implements = [];
                 c_body = (t1, xs, t2); c_attrs = [] } in
       [basic_entity v2, ClassDef c]

   | `Import_alias (v1, v2, v3, v4, v5) ->
       let _v1 = JS.token env v1 (* "import" *) in
       let _v2 = JS.identifier env v2 (* identifier *) in
       let _v3 = JS.token env v3 (* "=" *) in
       let _v4 = anon_choice_type_id_42c0412 env v4 in
       let _v5 = JS.semicolon env v5 in
       [] (* TODO *)

   | `Ambi_decl (v1, v2) ->
       let _v1 = JS.token env v1 (* "declare" *) in
       let v2 =
         (match v2 with
          | `Decl x -> declaration env x
          | `Global_stmt_blk (v1, v2) ->
              let v1 = JS.token env v1 (* "global" *) in
              let v2 = statement_block env v2 in
              let name = "!global!", v1 in
              let f = { f_attrs = []; f_params = [];
                        f_body = v2; f_rettype = None; } in
              (* TODO: DefTodo *)
              [basic_entity name, VarDef {v_kind = Const, v1;
                                          v_init = Some (Fun (f, None));
                                          v_type = None; }]
          | `Module_DOT_id_COLON_type (v1, v2, v3, v4, v5) ->
              let v1 = JS.token env v1 (* "module" *) in
              let _v2 = JS.token env v2 (* "." *) in
              let v3 = JS.identifier env v3 (* identifier *) in
              let _v4 = JS.token env v4 (* ":" *) in
              let v5 = type_ env v5 in
              let name = v3 in
              (* TODO: DefTodo *)
              [basic_entity name, VarDef { v_kind = Const, v1;
                                           v_init = None; v_type = Some v5 }]
         )
       in
       v2
  )

let toplevel env x = statement env x

let program (env : env) ((v1, v2) : CST.program) : program =
  let _v1 =
    (match v1 with
     | Some tok -> Some (JS.token env tok) (* pattern #!.* *)
     | None -> None)
  in
  let v2 = List.map (toplevel env) v2 |> List.flatten in
  v2

(*****************************************************************************)
(* Entry point *)
(*****************************************************************************)

type dialect = [ `Typescript | `TSX ]

let guess_dialect opt_dialect file : dialect =
  match opt_dialect with
  | Some x -> x
  | None ->
      (* TODO: should remove the no_sem below, bug in ml_to_generic.ml *)
      if file =~ ".*\\.tsx" then (* nosem *)
        `TSX
      else
        `Typescript

type cst_result = CST.program Tree_sitter_run.Parsing_result.t


let parse ?dialect file =
  let debug = false in
  H.wrap_parser
    (fun () ->
       let dialect = guess_dialect dialect file in
       Parallel.backtrace_when_exn := false;
       match dialect with
       | `Typescript ->
           let cst =
             Parallel.invoke Tree_sitter_typescript.Parse.file file () in
           (cst :> cst_result)
       | `TSX ->
           let cst =
             Parallel.invoke Tree_sitter_tsx.Parse.file file () in
           (cst :> cst_result)
    )
    (fun cst ->
       let env = { H.file; conv = H.line_col_to_pos file; extra = () } in

       if debug then (
         Printexc.record_backtrace true;
         CST.dump_tree cst;
       );

       program env cst
    )
