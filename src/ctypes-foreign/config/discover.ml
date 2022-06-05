module C = Configurator.V1

let () =
  let ctxname = ref "" in
  let ccomp_type = ref "" in
  let args = [
    ("-context_name", Arg.Set_string ctxname, "Dune %{context_name} variable");
    ("-ccomp_type", Arg.Set_string ccomp_type, "Dune %{ocaml-config:ccomp_type} variable");
  ] in
  C.main ~args ~name:"ffi" (fun c ->
      let backend =
        match Sys.os_type with
        | "Win32" | "Cygwin" -> "win"
        | _ -> "unix" in

      let fallback_pkg_config_flags () =
        let default : C.Pkg_config.package_conf = {
          libs = ["-lffi"];
          cflags = []
        } in
        let conf =
          match C.Pkg_config.get c with
          | None -> default
          | Some pc ->
            (match C.Pkg_config.query pc ~package:"libffi" with
            | None -> default
            | Some v -> v)
        in
        conf.cflags, conf.libs
      in

      let cflags, ldflags = 
        let open Dkml_c_probe.C_conf in
        match load_from_dune_context_name !ctxname with
        | Error msg -> failwith ("Failed loading C_conf in Dune Configurator. " ^ msg)
        | Ok conf -> 
          match compiler_flags_of_ccomp_type conf ~ccomp_type:!ccomp_type ~clibrary:"ffi" with
          | Error msg -> failwith ("Failed getting compiler flags from C_conf for ffi. " ^ msg)
          | Ok Some fl -> C_flags.cc_flags fl, C_flags.link_flags fl
          | Ok None ->
            (* If we can't use C probe, use pkg-config *)
            fallback_pkg_config_flags ()
      in

      let extra_ldflags =
        let f = "as_needed_test" in
        let ml = f ^ ".ml" in
        open_out ml |> close_out;
        match backend with
        |"win" -> ["-lpsapi"]
        |_ ->
          let res = C.Process.run_ok c "ocamlopt"
            ["-shared"; "-cclib"; "-Wl,--no-as-needed"; ml; "-o"; f^".cmxs"] in
          if res then ["-Wl,--no-as-needed"] else []
      in

      C.Flags.write_sexp "c_flags.sexp" cflags;
      C.Flags.write_lines "c_flags" cflags;
      C.Flags.write_sexp "c_library_flags.sexp" (ldflags @ extra_ldflags);
      C.Flags.write_lines "backend.sexp" [backend]
    )
