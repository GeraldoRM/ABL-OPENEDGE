/****************************************************************************
 *                  BRFOX TCS Ltda                                          *
 * PROGRAM       :  abl-json-curl-example.p                                 *
 * DESCRIPTION   :  ABL/CURL/JSON integration                               *
 * VERSION       :  QADEE 2016                                              *
 * DATE          :  19/02/2021                                              *
 * AUTHOR        :  Geraldo Moreira                                         *
 * CUSTOMER      :  xxxxxxxxxxxx                                            *
 * REMARKS       :  xxxxxxxxxxxx                                            *
 * LAST MODIFIED :                                                          *
 ****************************************************************************/

// Shared Variables and Classes
using Progress.Json.ObjectModel.*.
{us/bbi/mfdeclre.i}

// Parameters
define input parameter  row_mkp_hist  as   rowid                     no-undo.

// Variables                         
define variable lvc_envr              as   character                 no-undo.
define variable lvc_msg               as   character                 no-undo.
define variable lvc_request_cmd       as   character                 no-undo.
define variable lvc_response_cmd      as   character                 no-undo.
define variable lvc_request_file      as   character                 no-undo.
define variable lvc_response_file     as   character                 no-undo.
define variable lvc_old_session_dt    as   character                 no-undo.
define variable lvc_mkp_produto_id    as   character                 no-undo.
define variable lvc_mkp_sku_id        as   character                 no-undo.

define variable lvi_cont              as   integer                   no-undo.
define variable lvi_retry             as   integer                   no-undo.
define variable lvi_response          as   integer                   no-undo.


define variable lvl_error             like mfc_logical               no-undo.
define variable lvl_response          like mfc_logical               no-undo.

define variable long_json_request     as   longchar                  no-undo.
define variable long_json_response    as   longchar                  no-undo.

define variable obj_json_parser       as   ObjectModelParser         no-undo.

define variable json_obj_response     as   JsonObject                no-undo.
define variable json_obj_productData  as   JsonObject                no-undo.
define variable json_obj_skuData      as   JsonObject                no-undo.
define variable json_arr_skus         as   JsonArray                 no-undo.


define temp-table images no-undo
  fields thumbnail    as character
  fields small        as character
  fields average      as character
  fields big          as character
  fields link         as character
  fields main         as logical
  fields number       as integer
  index idx_images
        number.

assign
 lvc_old_session_dt     = session:numeric-format
 session:numeric-format = "american"
 no-error.
 
// Get QAD Environment
{us/bbi/gprun.i ""yyget-qad-envr.p"" "(output lvc_envr, output lvi_retry)"}

mainloop:
repeat:

   find first mkp_hist exclusive-lock
        where rowid(mkp_hist) = row_mkp_hist
        no-wait no-error.
        
   if not available mkp_hist or
      locked(mkp_hist) then leave mainloop.
      
   find first ptmkp_mstr exclusive-lock
        where ptmkp_mstr.ptmkp_domain  = global_domain
        and   ptmkp_mstr.ptmkp_mkplace = mkp_hist.mkp_marketplace
        and   ptmkp_mstr.ptmkp_part    = mkp_hist.mkp_part
        no-wait no-error.
        
   if not available ptmkp_mstr or
      locked(ptmkp_mstr) then leave mainloop.
         
   assign 
    lvc_request_cmd    = ""
    lvc_response_cmd   = ""
    lvc_msg            = ""
    long_json_request  = ""
    long_json_response = ""    
    .
   
   find first mkpc_ctrl no-lock
        where mkpc_ctrl.mkpc_domain      = global_domain
        and   mkpc_ctrl.mkpc_envr        = lvc_envr
        and   mkpc_ctrl.mkpc_marketplace = mkp_hist.mkp_marketplace
        and   mkpc_ctrl.mkpc_site        = mkp_hist.mkp_site
        no-error.
        
   if available mkpc_ctrl then      
      find first mkpd_ctrl no-lock
           where mkpd_ctrl.oid_mkpc_ctrl = mkpc_ctrl.oid_mkpc_ctrl
           and   mkpd_ctrl.mkpd_api_type = mkp_hist.mkp_interface
           no-error.
           
   if not available mkpc_ctrl or 
      not available mkpd_ctrl then do:
      assign
       lvc_msg                = "Parametros nao encontrados: " +
                                "Ambiente: " + lvc_envr        +
                                " / Local: " + mkp_site  
       mkp_hist.mkp_send_date = now
       mkp_hist.mkp_request   = ""
       mkp_hist.mkp_response  = ""
       mkp_hist.mkp_msg       = lvc_msg    
       mkp_hist.mkp_error     = yes
       .
       leave mainloop.
   end.    
   
   if mkp_hist.mkp_interface <> "PRODUTO-DELETE" then
      run GetRequest.
   else do:
      find first ptmkp_mstr no-lock 
           where ptmkp_domain  = global_domain
           and   ptmkp_mkplace = mkp_hist.mkp_marketplace
           and   ptmkp_part    = mkp_hist.mkp_part
           no-error.

      assign 
       lvc_mkp_produto_id = (if lvc_envr = "PRD" then 
                            ptmkp_mstr.ptmkp_produto_id_mkp_prd
                            else ptmkp_mstr.ptmkp_produto_id_mkp_tst)
       lvc_mkp_sku_id     = (if lvc_envr = "PRD" then 
                            ptmkp_mstr.ptmkp_sku_id_mkp_prd
                            else ptmkp_mstr.ptmkp_sku_id_mkp_tst)
       .                     
   end.
       
   assign
    lvc_request_file  = mkpc_ctrl.mkpc_path                       +
                        "request/"                                +
                        lower(trim(mkp_hist.mkp_interface) + "_") +
                        string(year(today),"9999")                +
                        string(month(today),"99")                 +
                        string(day(today),"99")                   +
                        "_"                                       +
                        string(time,"99999")                      +
                        ".curl"
    lvc_response_file = mkpc_ctrl.mkpc_path                       +
                        "response/"                               +    
                        lower(trim(mkp_hist.mkp_interface) + "_") +
                        string(year(today),"9999")                +
                        string(month(today),"99")                 +
                        string(day(today),"99")                   +
                        "_"                                       +
                        string(time,"99999")                      +
                        ".json"
    lvc_request_cmd   = 
     "curl --silent --location --request "                                 +
     trim(mkpd_ctrl.mkpd_api_method)                                       +
     " '"                                                                  +
     trim(mkpc_ctrl.mkpc_base_url)                                         +
     replace(mkpd_ctrl.mkpd_api_uri,'<id>',trim(lvc_mkp_produto_id))       +
     "' "                                                                  +
     "--header 'accept: application/json' "                                +
     "--header 'token: "                                                   +
     trim(mkpc_ctrl.mkpc_app_token)                                        +
     "' "                                                                  +
     "--header 'tenant: "                                                  +
     trim(mkpc_ctrl.mkpc_tenant_id)                                        +
     "' "                                                                  +
     "--header 'application_id: "                                          +
     trim(mkpc_ctrl.mkpc_app_id)                                           +
     "' "                                                                  +
     "--header 'Content-Type: application/json' "                          +  
     (if mkp_interface <> "PRODUTO-DELETE" then     
         "--data " + "'" + long_json_request + "'" else '')                +
     " > " + lvc_response_file
    lvl_response = no
    lvl_error    = no
    .                                               
   
   output to value(lvc_request_file).
   put unformatted lvc_request_cmd skip.
   output close.
   unix silent sh value(lvc_request_file).
      
   do lvi_cont = 1 to lvi_retry:
      if search(lvc_response_file) = ? then 
         pause 1 no-message.
      else do:
         copy-lob file lvc_response_file to
            long_json_response convert target codepage "UTF-8".

         if mkp_hist.mkp_interface <> "PRODUTO-DELETE" then do:
            obj_json_parser = new ObjectModelParser() no-error.
            if not error-status:error  then
               json_obj_response = 
                cast(obj_json_parser:Parse(long_json_response),JsonObject)
                no-error.
            if not error-status:error  then
               json_obj_productData =
                json_obj_response:GetJsonObject("productData") no-error.
            if not error-status:error  then
               lvc_mkp_produto_id = json_obj_productData:GetCharacter("id") 
                                    no-error. 
            if not error-status:error  then
               json_arr_skus = json_obj_response:GetJsonArray("skus").
            if not error-status:error  then
               json_obj_skuData = json_arr_skus:GetJsonObject(1) no-error.
            if not error-status:error  then
               json_obj_skuData = json_obj_skuData:GetJsonObject("skuData") 
                                  no-error.
            if not error-status:error  then             
               lvc_mkp_sku_id = json_obj_skuData:GetCharacter("id") no-error.
            
            if error-status:error then 
               assign 
                lvl_error = yes
                lvc_msg   = "ERRO: Interface falhou".
            else do:
                lvc_msg   = "OK: Interface processada".
                find first ptmkp_mstr exclusive-lock
                     where ptmkp_mstr.ptmkp_domain = global_domain
                     and   ptmkp_mstr.ptmkp_mkplace = mkp_hist.mkp_marketplace
                     and   ptmkp_mstr.ptmkp_part = mkp_hist.mkp_part
                     no-error.
                  
                if lvc_envr = "PRD" then
                   assign
                    ptmkp_mstr.ptmkp_produto_id_mkp_prd = lvc_mkp_produto_id
                    ptmkp_mstr.ptmkp_sku_id_mkp_prd     = lvc_mkp_sku_id
                    .
                else
                   assign
                    ptmkp_mstr.ptmkp_produto_id_mkp_tst = lvc_mkp_produto_id
                    ptmkp_mstr.ptmkp_sku_id_mkp_tst     = lvc_mkp_sku_id
                    .
                release ptmkp_mstr.
            end.    
         end.
         else do:
            obj_json_parser = new ObjectModelParser() no-error.
            if not error-status:error  then
               json_obj_response = 
                cast(obj_json_parser:Parse(long_json_response),JsonObject)
                no-error.
            if not error-status:error then
               lvi_response = json_obj_response:GetInteger("code") no-error.
            if not error-status:error then    
               lvc_msg = json_obj_response:GetCharacter("message") no-error.
                
            if error-status:error then 
               assign 
                lvl_error = yes
                lvc_msg   = "ERRO: Interface falhou"
                .
            else 
               if lvi_response = 200 or
                  lvi_response = 201 or
                  lvi_response = 203 then 
                  assign
                   lvl_error = no
                   lvc_msg   = "OK: Interface processada"
                   .
               else   
                 lvl_error = yes.
         end.
         
         lvl_response = yes.                                  
         leave.
      end.
   end.
   
   if not lvl_response then 
      assign
       lvl_error = yes
       lvc_msg   = "ERRO: interface sem resposta".
       
   assign
    mkp_hist.mkp_send_date = now
    mkp_hist.mkp_request   = string(long_json_request)    
    mkp_hist.mkp_response  = string(long_json_response)
    mkp_hist.mkp_msg       = lvc_msg    
    mkp_hist.mkp_error     = lvl_error
    .
   release mkp_hist.
   
   if mkpc_ctrl.mkpc_del_log then do:
      unix silent rm -f value(lvc_request_file)  2> /dev/null.
      unix silent rm -f value(lvc_response_file) 2> /dev/null.
   end.   
   
   leave mainloop.
end. // mainloop

delete object json_obj_response    no-error.
delete object json_obj_productData no-error.
delete object json_obj_skuData     no-error.
delete object json_arr_skus        no-error.

session:numeric-format = lvc_old_session_dt.

procedure GetRequest.

   define variable json_obj_main       as Progress.Json.ObjectModel.JsonObject.
   define variable json_obj_productData 
                                       as Progress.Json.ObjectModel.JsonObject.
   define variable json_obj_codes      as Progress.Json.ObjectModel.JsonObject.
   define variable json_obj_productDimensionData 
                                       as Progress.Json.ObjectModel.JsonObject.
   define variable json_obj_packageDimensionData
                                       as Progress.Json.ObjectModel.JsonObject.
   define variable json_obj_taxData    as Progress.Json.ObjectModel.JsonObject.
   define variable json_obj_ncmData    as Progress.Json.ObjectModel.JsonObject.
   define variable json_obj_categoryData
                                       as Progress.Json.ObjectModel.JsonObject.
   define variable json_obj_categories as Progress.Json.ObjectModel.JsonObject.
   define variable json_obj_attributes as Progress.Json.ObjectModel.JsonObject.
   define variable json_obj_skus       as Progress.Json.ObjectModel.JsonObject.
   define variable json_obj_skuData    as Progress.Json.ObjectModel.JsonObject.
   define variable json_obj_errors     as Progress.Json.ObjectModel.JsonObject.
   define variable json_obj_priceData  as Progress.Json.ObjectModel.JsonObject.
   define variable json_obj_stockData  as Progress.Json.ObjectModel.JsonObject.
   define variable json_obj_images     as Progress.Json.ObjectModel.JsonObject.
   define variable json_obj_skattributes 
                                       as Progress.Json.ObjectModel.JsonObject.

   define variable json_arr_codes        as JsonArray                  no-undo.
   define variable json_arr_categories   as JsonArray                  no-undo.
   define variable json_arr_attributes   as JsonArray                  no-undo.
   define variable json_arr_skus         as JsonArray                  no-undo.
   define variable json_arr_errors       as JsonArray                  no-undo.
   define variable json_arr_images       as JsonArray                  no-undo.
   define variable json_arr_skattributes as JsonArray                  no-undo.

   define variable lvc_part_desc         as character                  no-undo.
   define variable lvc_tags              as character                  no-undo.
   define variable lvc_link_images       as character                  no-undo.  
   define variable lvc_um_desc           as character                  no-undo.
   define variable lvc_category_desc     as character                  no-undo.

   define variable lvi_qty_inv           as integer                    no-undo.
   define variable lvi_count_image       as integer                    no-undo.
   define variable lvi_cont              as integer                    no-undo.

   define variable lvd_price             as decimal   decimals 2       no-undo.
 
/* Estrutura JSON (o=Object r=Array)
.   o main 
.     o productData 
.     r codes
.     o productDimensionData
.     o packageDimensionData
.     o taxData 
.     o ncmData
.     o categoryData
.     r categories
.     r attributes
.     r skus
.       o skuData
.       r codes
.       r errors
.       o priceData
.       o stockData
.       o packageDimensionData
.       r images
.       r sku_attributes
*/  

   empty temp-table images no-error.
   assign
    lvc_link_images = "https://imagens-links.com/IMAGES-STORE"
    lvi_count_image = 0
    .
 
   for first code_mstr no-lock
       where code_mstr.code_domain  = global_domain
       and   code_mstr.code_fldname = "IMAGES-STORE"
       and   code_mstr.code_value   = "MARKETPLACE"
       :
       lvc_link_images = trim(code_mstr.code_cmmt).
   end.

   find first ptmkp_mstr no-lock 
        where ptmkp_domain = global_domain
        and   ptmkp_mkplace = mkp_hist.mkp_marketplace
        and   ptmkp_part    = mkp_hist.mkp_part
        no-error.

   find first pt_mstr no-lock 
        where pt_mstr.pt_domain = global_domain
        and   pt_mstr.pt_part   = ptmkp_mstr.ptmkp_part
        no-error.
     
   find first prod_compl no-lock
        where prod_compl.domain = global_domain
        and   prod_compl.part   = ptmkp_mstr.ptmkp_part
        no-error.     
          
   find first ld_det no-lock
       where ld_det.ld_domain = global_domain
       and   ld_det.ld_site   = mkpc_ctrl.mkpc_site
       and   ld_det.ld_loc    = mkpc_ctrl.mkpc_loc
       and   ld_det.ld_part   = ptmkp_mstr.ptmkp_part
       no-error.
     
   assign               
    lvc_part_desc      = pt_mstr.pt_desc1 +  pt_mstr.pt_desc2
    lvd_price          = ptmkp_mstr.ptmkp_price
    lvi_qty_inv        = (if available ld_det then ld_det.ld_qty_oh else 0)
    lvc_mkp_produto_id = (if lvc_envr = "PRD" then 
                         ptmkp_mstr.ptmkp_produto_id_mkp_prd
                         else ptmkp_mstr.ptmkp_produto_id_mkp_tst)
    lvc_mkp_sku_id     = (if lvc_envr = "PRD" then 
                         ptmkp_mstr.ptmkp_sku_id_mkp_prd
                         else ptmkp_mstr.ptmkp_sku_id_mkp_tst)
    .
 
   do lvi_cont = 1 to 10:
      if ptmkp_mstr.ptmkp_tags[lvi_cont] <> "" then
         lvc_tags = lvc_tags + ptmkp_mstr.ptmkp_tags[lvi_cont] + ",".   
      
      if ptmkp_mstr.ptmkp_image[lvi_cont] <> "" then do:
      
         lvi_count_image = lvi_count_image + 1.
      
         create images.
         assign
          images.thumbnail = lvc_link_images + ptmkp_mstr.ptmkp_image[lvi_cont]
          images.small     = lvc_link_images + ptmkp_mstr.ptmkp_image[lvi_cont]
          images.average   = lvc_link_images + ptmkp_mstr.ptmkp_image[lvi_cont]
          images.big       = lvc_link_images + ptmkp_mstr.ptmkp_image[lvi_cont]
          images.link      = lvc_link_images + ptmkp_mstr.ptmkp_image[lvi_cont]
          images.main      = (if lvi_count_image = 1 then yes else no)
          images.number    = lvi_count_image
          .
      end.
   end.

   find first mkpgen_mstr no-lock
        where mkpgen_mstr.mkpgen_domain   = global_domain
        and   mkpgen_mstr.mkpgen_mktplace = ptmkp_mstr.ptmkp_mkplace
        and   mkpgen_mstr.mkpgen_fldname  = "UNIDADE-MEDIDA"
        and   mkpgen_mstr.mkpgen_code     = ptmkp_mstr.ptmkp_um
        no-error.
   lvc_um_desc = (if available mkpgen_mstr then 
                  mkpgen_mstr.mkpgen_desc else "").
                 
   find first mkpgen_mstr no-lock
        where mkpgen_mstr.mkpgen_domain = global_domain
        and   mkpgen_mstr.mkpgen_mktplace = ptmkp_mstr.ptmkp_mkplace
        and   mkpgen_mstr.mkpgen_fldname  = "CATEGORIA"
        and   mkpgen_mstr.mkpgen_code     = ptmkp_mstr.ptmkp_category
        no-error.
   lvc_category_desc = (if available  mkpgen_mstr then
                        mkpgen_mstr.mkpgen_desc_mktplace else "").
                                       
   // Main object                
   json_obj_main = new JsonObject().
   json_obj_main:add("active",ptmkp_mstr.ptmkp_active).
   json_obj_main:add("tenant",mkpc_ctrl.mkpc_tenant_id).
   json_obj_main:add("account","").

   // productData object 
   json_obj_productData = new JsonObject().
   json_obj_productData:add("active",ptmkp_mstr.ptmkp_active).
   json_obj_productData:add("productName",lvc_part_desc).
   json_obj_productData:add("description",
                            replace(ptmkp_mstr.ptmkp_desc_html,"\n","<br>")).
   json_obj_productData:add("descriptionHTML",
                            replace(ptmkp_mstr.ptmkp_desc_html,"\n","<br>")).
   json_obj_productData:add("brand",ptmkp_mstr.ptmkp_brand).
   json_obj_productData:add("tags",lvc_tags).
   json_obj_productData:add("warranty",ptmkp_mstr.ptmkp_warranty).
   json_obj_productData:add("variant",true).
   json_obj_productData:add("unit",ptmkp_mstr.ptmkp_um).
   json_obj_productData:add("unitInitials",lvc_um_desc).

   // codes array
   json_obj_codes = new JsonObject().
   json_obj_codes:add("code",ptmkp_mstr.ptmkp_part).
   json_arr_codes = new JsonArray(0).
   json_arr_codes:Add(0,json_obj_codes).

   // productDimensionData object
   json_obj_productDimensionData = new JsonObject().
   json_obj_productDimensionData:add("width",integer(prod_compl.larg   * 100)).
   json_obj_productDimensionData:add("height",integer(prod_compl.alt   * 100)). 
   json_obj_productDimensionData:add("depth",integer(prod_compl.compri * 100)).
   json_obj_productDimensionData:add("grossWeight",pt_mstr.pt_ship_wt).

   // packageDimensionData object
   json_obj_packageDimensionData = new JsonObject().
   json_obj_packageDimensionData:add("width",integer(prod_compl.largco * 100)).
   json_obj_packageDimensionData:add("height",integer(prod_compl.altco * 100)).
   json_obj_packageDimensionData:add("depth",
                                           integer(prod_compl.comprico * 100)).
   json_obj_packageDimensionData:add("grossWeight",pt_mstr.pt_ship_wt).

   // taxData object
   json_obj_taxData = new JsonObject().
   json_obj_taxData:add("icmsOriginId",pt_mstr.pt_origin).
   json_obj_taxData:add("icmsOriginName","").

   // ncmData object
   json_obj_ncmData = new JsonObject().
   json_obj_ncmData:add("id",pt_mstr.pt_fiscal_class).
   json_obj_ncmData:add("ncm",pt_mstr.pt_fiscal_class).
   json_obj_TaxData:add("ncmData",json_obj_ncmData).

   // categoryData oject
   json_obj_categoryData = new JsonObject().
   json_obj_categoryData:add("id",ptmkp_mstr.ptmkp_category).
   json_obj_categoryData:add("code",ptmkp_mstr.ptmkp_category).
   json_obj_categoryData:add("name",lvc_category_desc).

   // categories array
   json_obj_categories = new JsonObject().
   json_obj_categories:add("channel","MARKETPLACE").
   json_obj_categories:add("id","").
   json_obj_categories:add("name","").
   json_obj_categories:add("id1","").
   json_obj_categories:add("name1","").
   json_obj_categories:add("id2","").
   json_obj_categories:add("name2","").
   json_obj_categories:add("id3","").
   json_obj_categories:add("name3","").
   json_obj_categories:add("id4","").
   json_obj_categories:add("name4","").
   json_obj_categories:add("id5","").
   json_obj_categories:add("name5","").
   json_obj_categories:add("id6","").
   json_obj_categories:add("name6","").
   json_obj_categories:add("id7","").
   json_obj_categories:add("name7","").
   json_obj_categories:add("id8","").
   json_obj_categories:add("name8","").
   json_arr_categories = new JsonArray(0).
   json_arr_categories:Add(0,json_obj_categories).

   // attributes array
   json_obj_attributes = new JsonObject().
   json_obj_attributes:add("id","").
   json_obj_attributes:add("name","").
   json_obj_attributes:add("value","").
   json_obj_attributes:add("required",true).
   json_arr_attributes = new JsonArray(0).
   json_arr_attributes:Add(0,json_obj_attributes).

   // skuData object
   json_obj_skuData = new JsonObject().
   json_obj_skuData:add("sku",ptmkp_mstr.ptmkp_part).
   json_obj_skuData:add("skuName",lvc_part_desc).
   json_obj_skuData:add("gtin",prod_compl.codbar).
   json_obj_skuData:add("model",ptmkp_mstr.ptmkp_model).
   json_obj_skuData:add("crossdockingDays",ptmkp_mstr.ptmkp_lead_time).
   json_obj_skuData:add("supplierCode","PARTNER").
   json_obj_skuData:add("erpCode","QAD").
   json_obj_skuData:add("establishmentCode","").
   json_obj_skuData:add("moderationStatus","").
   json_obj_skuData:add("moderationDate","").

   // errors array
   json_obj_errors = new JsonObject().
   json_obj_errors:add("code",0).
   json_obj_errors:add("type","").
   json_obj_errors:add("message","").
   json_arr_errors = new JsonArray(0).
   json_arr_errors:add(0,json_obj_errors).

   //priceData object
   json_obj_priceData = new JsonObject().
   json_obj_priceData:add("fromPrice",lvd_price).
   json_obj_priceData:add("price",lvd_price).
   json_obj_priceData:add("costPrice",0).

   // stockData object
   json_obj_stockData = new JsonObject().
   json_obj_stockData:add("stock",lvi_qty_inv).
   json_obj_stockData:add("minStock",0).

   // images array
   json_arr_images = new JsonArray(0).
   for each images no-lock
       by images.number desc
       :
       json_obj_images = new JsonObject().
       json_obj_images:add("thumbnail",images.thumbnail).
       json_obj_images:add("small",images.small).
       json_obj_images:add("average",images.average).
       json_obj_images:add("big",images.big).
       json_obj_images:add("link",images.link).
       json_obj_images:add("main",images.main).
       json_obj_images:add("number",images.number).
       json_arr_images:add(0,json_obj_images).
   end.

   //sku attributes array   
   json_obj_skattributes = new JsonObject().
   json_obj_skattributes:add("name","").
   json_obj_skattributes:add("value","").
   json_obj_skattributes:add("centauro","").
   json_obj_skattributes:add("cnova","").
   json_obj_skattributes:add("mercadoLivre","").
   json_obj_skattributes:add("netshoes","").
   json_obj_skattributes:add("magazineLuiza","").
   json_obj_skattributes:add("b2w","").
   json_obj_skattributes:add("walmart","").
   json_obj_skattributes:add("amazon","").
   json_obj_skattributes:add("buscape","").
   json_obj_skattributes:add("carrefour","").
   json_obj_skattributes:add("dafiti","").
   json_obj_skattributes:add("cizzaMagazine","").
   json_obj_skattributes:add("zoom","").
   json_obj_skattributes:add("lojaMecanico","").
   json_arr_skattributes = new JsonArray(0).
   json_arr_skattributes:Add(0,json_obj_skattributes).
   json_obj_skattributes = new JsonObject().
   json_obj_skattributes:add("attributes",json_arr_skattributes).

   // skus object
   json_obj_skus = new JsonObject().
   json_obj_skus:add("active",ptmkp_mstr.ptmkp_active).
   json_obj_skus:add("skuData",json_obj_SkuData).
   json_obj_skus:add("codes",json_arr_codes).
   json_obj_skus:add("errors",json_arr_errors).
   json_obj_skus:add("priceData",json_obj_priceData).
   json_obj_skus:add("stockData",json_obj_stockData).
   json_obj_skus:add("packageDimensionData",json_obj_packageDimensionData).
   json_obj_skus:add("images",json_arr_images).
   json_obj_skus:add("attributes",json_arr_skattributes).

   json_arr_skus = new JsonArray().
   json_arr_skus:add(0,json_obj_skus).

   // Build Json File
   json_obj_main:add("productData",json_obj_productData).
   json_obj_main:add("codes",json_arr_codes).
   json_obj_main:add("productDimensionData",json_obj_productDimensionData).
   json_obj_main:add("packageDimensionData",json_obj_packageDimensionData).
   json_obj_main:add("taxData",json_obj_taxData).
   json_obj_main:add("categoryData",json_obj_categoryData).
   json_obj_main:add("categories",json_arr_categories).
   json_obj_main:add("attributes",json_arr_attributes).
   json_obj_main:add("skus",json_arr_skus).

   json_obj_main:write(long_json_request,false).

   delete object json_obj_main                 no-error.
   delete object json_obj_productData          no-error.
   delete object json_obj_codes                no-error.
   delete object json_obj_productDimensionData no-error.
   delete object json_obj_packageDimensionData no-error.
   delete object json_obj_taxData              no-error.
   delete object json_obj_ncmData              no-error.
   delete object json_obj_categoryData         no-error.             
   delete object json_obj_categories           no-error.
   delete object json_obj_attributes           no-error.
   delete object json_obj_skus                 no-error.
   delete object json_obj_skuData              no-error.
   delete object json_obj_codes                no-error.
   delete object json_obj_errors               no-error.
   delete object json_obj_priceData            no-error.
   delete object json_obj_stockData            no-error.
   delete object json_obj_images               no-error.
   delete object json_obj_skattributes         no-error.
end. // GetRequest

