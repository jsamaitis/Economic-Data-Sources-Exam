###------------------- missingHours -----------
# Input:
#   * datetime formato vektorius (vector_datetime, POSIXct);
#   * pradine valanda nuo kurios prasideda datos (starting_hour, integer);
#   * galima pasirinkti kad atspausdintu tarp kokiu datu truko valandu (warnings_print, logical)
#   * galima pasirinkti kad grazintu lentele su praleistomis valandomis. (warnings_return, logical)
# 
# Output:
#   * warnings lentele (warnings, tibble)
#
missingHours <-
  function(vector_datetime,
           starting_hour = 11,
           warnings_print = F,
           warnings_return = F) {
    
    # Pradine valanda nuo kurios prasideda failai.
    hr = starting_hour
    
    # Lentele i kuria desime praleistus intervalus.
    warnings <-
      tibble(
        "start_date" = as_datetime(character()),
        "end_date" = as_datetime(character()),
        "time_difference" = character()
      )
    
    
    for (i in 1:length(vector_datetime)) {
      # Jei valanda is vektoriaus neatitinka valandos, kuri turetu buti, ikeliame datu intervala.
      if (hour(vector_datetime[i]) != hr) {
        warnings <-
          add_row(
            warnings,
            start_date = vector_datetime[i - 1],
            end_date = vector_datetime[i],
            time_difference = as.character.Date(vector_datetime[i] - vector_datetime[i - 1])
          )
      }
      # Kai neatitinka, didiname valandas kol atitinka. Jei 24, pradedame is naujo (0-23).
      while (hour(vector_datetime[i]) != hr) {
        hr = hr + 1
        if (hr == 24)
          hr = 0
      }
      
      # Jei viskas k, tesiame tikrinim�.
      hr = hr + 1
      if (hr == 24)
        hr = 0
    }
    
    # Jeigu kazkas negerai, pranesame vartotojui.
    if (nrow(warnings) != 0)
      warning("Vektoriuje yra praleistu datu.")
    
    if (warnings_print == T)
      print(warnings)
    
    if (warnings_return == T)
      return(warnings)
  }


###------------------- getSunriseTimes ---------
# Input:
#   * html failo lentel�s (orai_nodes, xml_nodeset).
# 
# Output:
#   * i� to failo i�gautas saul�s tek�jimo ir leidimosi laikas. Nereikalingas, ta�iau galimyb� t� padaryti 
# yra (orai_sunrise_times, character).
#
getSunriseTimes <- function(orai_nodes){
  
  # I� metadata dalies, i�renka laikus.
  orai_sunrise_times <- orai_nodes %>%
    html_nodes(xpath = '//tr//*[@class="day_metainfo"]//div') %>%
    html_text() %>%
    # Sutvarko netvarking� string'�.
    str_replace_all("[\r\n*{\t}]" , "") %>%
    str_split("                ")
  
  return(orai_sunrise_times)
}


###------------------ getRawDates (raw) --------
# Input:
#   * html failo lentel�s (orai_nodes, xml_nodeset).
# 
# Output:
#   * i� to failo i�gautos datos, grynuoju character formatu. (orai_dates_text, character)
#
getRawDates <- function(orai_nodes){
  
  # Getting text from date nodes
  orai_dates_text <- orai_nodes %>%
    html_nodes(xpath = '//tr//*[@class="day_head"]') %>%
    html_text()
  
  return(orai_dates_text)
}


###------------------ getDatesEnglish -----------
# Input:
#   * html failo lentel�s (orai_nodes, xml_nodeset).
#   * parametras kuris leid�ia datas gra�inti character arba POSIXct formatu (as_string, logical)
# 
# Output:
#   * Datos paverstos i� gryn� Lietuvi�k� � Anglu k., datos arba teksto formatu 
# (dates_final_char, tibble, character // dates_final, tibble, POSIIXct)
#
getDatesEnglish <- function(orai_nodes, as_string = TRUE){
  
  # Nuskaito grynasias datas
  dates_lith <- enc2native(tolower(getRawDates(orai_nodes)))
  
  # M�nesi� pavadinimai. ISSUE: JEIGU NAUDOJI PER SOURCE, NENUSKAITO LIETUVISKU RAIDZIU
  months_lith <- c("sausio", "vasario", "kovo", "baland�io", "gegu��s", "bir�elio", "liepos", "rugpj��io", "rugs�jo", "spalio", "lapkri�io", "gruod�io")
  months_en <- tolower(month.name)
  
  # Patternas, randantis angli�kus lietuvi�k� m�nesi� pavadinim� atitikmenis.
  pattern <- str_c(
    "(",
    str_c(months_lith, collapse = "|"),
    "){1}",
    '\\s\\d+'
  )
  
  # Sumatchina ir sudeda � lentel�.
  dates_match <- as.tibble(str_match(dates_lith, pattern))
  
  # Sutvarko gryn�j� tekst� ir padaro j� datetime formatu.
  dates_final <- dates_match %>%
    mutate(
      # I�traukia tik m�nesio dien� skai�i�.
      day_of_month = as.numeric(
        str_match(V1, "\\d+")
      ),
      # Pagal atitinkan�i� viet� vektoriuje, paver�ia lietuvi�kus m�nesius � angli�kus.
      month_en = months_en[match(dates_match$V2, months_lith)]) %>%
    # Sujungia � m�nesis diena format�.
    mutate(date_final = str_c(month_en, day_of_month, sep = " ")) %>%
    # Paver�ia � datetime objekt�.
    mutate(date_final = parse_date_time(date_final, "%m %d", tz = Sys.timezone())) %>%
    select(date_final)
  
  # Gra�inamas arba teksto arba datos formatu.
  if (as_string == TRUE){
    dates_final_char <- dates_final %>%
      mutate(date_final = strftime(date_final, format = "%B %d, %A")) %>%
      pull(date_final)
    return(dates_final_char)
  } else {
    return(dates_final %>% pull(date_final))
  }
}


###------------------- getWeatherTable ---------
# Input:
#   * miesto pavadinimas (city, character)
#   * github fail� pavadinim� vektorius, gautas prad�ioje (weather_path, character)
# 
# Output:
#   * visos or� prognoz�s tam tikram miestui, vienoje lentel�je (weather_table_final, tibble)
#
getWeatherTable <- function(city, weather_path) {
  
  # Tikrina ar miestas teisingai pasirinktas.
  city <- tolower(city)
  if (!(city %in%  c("vilnius", "kaunas", "klaipeda")))
    stop("Miestas n�ra i� galim� variant�. (Vilnius, Kaunas, Klaipeda)")
  
  city_pattern <- str_c(city, "_")
  
  # Atrenka tik pasirinkto miesto failus.
  weather_path_city <- weather_path %>%
    .[which(str_match(weather_path, "\\w*_") == city_pattern)]
  
  # Padaro i� j� nuorod� � GitHub.
  weather_urls <-
    str_c(
      "https://raw.githubusercontent.com/vzemlys/eda_2017/master/data/",
      weather_path_city
    )
  
  
  weather_table_final <- tibble()
  
  # Kiekvienai nuorodai padarys po lentel� ir prijungs priei galutin�s
  for (weather_url in weather_urls) {
    
    # Nuskaito fail�.
    weather <- read_html(getURL(weather_url))
    
    # Atrenka oraiTable lenteles.
    weather_nodes <- weather %>%
      html_nodes(xpath = '//*[@class="weather_box"]//table')
    
    # html_table sudeda � lenteles, bet prastai.
    weather_table_raw <- weather_nodes %>%
      html_table()
    
    
    
    ### Nuo �ia kartojasi kodas, naudotas 7-8 u�duotyje.
    
    weather_table_temp <- tibble()
    
    # Funkcij� kuri gra�ins mums dat� (Detaliau yra apra�yta pa�iame faile getDatesEnglish.R).
    weather_dates <-
      getDatesEnglish(weather_nodes, as_string = T) #String formatas gra�iau atrodo.
    
    # Sutvarko visas lenteles ir sudeda � vien�.
    for (i in seq_along(weather_table_raw)) {
      
      temp_tbl <- as.tibble(weather_table_raw[[i]])
      temp_tbl_final <- temp_tbl %>%
        # Pa�alina icon�li� stulpel� (debesuota, saul�ta, etc.).
        select(-X2) %>%
        # Pervadina stulpelius atitinkamais pavadinimais.
        `colnames<-`(slice(., 2)) %>%
        # Pa�alin� eilut�, kuri� naudojom pavadinimams sud�ti.
        slice(3:n()) %>%
        # Prideda datos ir laiko eilutes.
        mutate("Data" = weather_dates[i]) %>%
        select(Data, Laikas:Krituliai) %>%
        separate(Laikas,
                 into = c("Pradzia", "Pabaiga"),
                 sep = " - ") %>%
        mutate(Pradzia = as.integer(str_sub(Pradzia, end = 2)),
               Pabaiga = as.integer(str_sub(Pabaiga, end = 2)))
      
      # Prideda sutvarkyt� lentel�.
      weather_table_temp <-
        rbind(weather_table_temp, temp_tbl_final)
    }
    
    # Prided� lenteli� lentel� prie galutin�s lentel�s.
    weather_table_final <- weather_table_final %>%
      bind_rows(weather_table_temp)
  }
  
  # Pridedu stulpeli su miesto pavadinimu
  return(weather_table_final %>% add_column("Miestas" = city))
}


###------------------- fixJson ---------
# Input:
#   * JSON(?) formato, bet sugadintas failas (weird_json, raw text)
# 
# Output:
#   * sutvarkyta lentel� (tibble)
#
fixJson <- function(weird_json) {
  
  # Pa�alina teksto dalis kurios lau�o kod�, gra�ina lentel�.
  return(
    str_replace_all(weird_json, "wup\\(|\\);", "") %>%
      str_replace(",\n\\}", "\n\\}") %>%
      fromJSON() %>%
      map(as.numeric) %>%
      as_tibble()
  )
}


###------------------- getWeatherCiurlionis ---------
# Input:
#   * github fail� pavadinim� vektorius, gautas prad�ioje (weather_path, character)
# 
# Output:
#   * visos or� prognoz�s ciurlionio sto�iai, vienoje lentel�je (weather_table_final, tibble)
#
getWeatherCiurlionis <- function(weather_path) {
  
  # Atrenka fail� pavadinimus.
  weather_path_city <- weather_path %>%
    .[which(str_match(weather_path, "\\w*_") == "ciurlionis_")]
  
  # Padaro i� j� urls
  weather_urls <-
    str_c(
      "https://raw.githubusercontent.com/vzemlys/eda_2017/master/data/",
      weather_path_city
    )
  
  weather_table_final <- tibble()
  
  # Parsiun�ia failus ir sudeda � lentel�.
  for (i in seq_along(weather_urls)){
    
    weather_raw <- getURL(weather_urls[i])
    
    if (weather_raw != ""){
      # Sutvarko format� ir nuskaito kaip JSON, po to pakei�ia � numeric i� character.
      weather_table_temp <- fixJson(weather_raw)
      
      weather_table_temp <- weather_table_temp %>%
        #Prideda laiko ir datos stulpelius, pagal failo pavadinim�.
        mutate(Date = ymd(str_match(weather_path[i], "\\d{4}-\\d{2}-\\d{2}")),
               Time = str_match(weather_path[i], "\\d{2}:\\d{2}:\\d{2}")) %>%
        # I�skirsto laik�.
        separate(Time, into = c("Hour", "Minute", "Second"), sep = ":") %>%
        # I�d�lioja patogiu formatu.
        select(Date:Second, Temp:WD)
      
    } else {
      next()
    }
    
    # Sudeda � lentel�.
    weather_table_final <- weather_table_final %>%
      bind_rows(weather_table_temp)
  }
  return(weather_table_final)
}