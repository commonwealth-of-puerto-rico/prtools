require 'csv'

# Let's load the CSV and save it into an array of objects

path = "/Users/miguel/Dropbox/CorpsBAK.csv"
dirty_data = []
columns = []
index = 0

CSV.foreach(path, encoding: "ISO8859-1") do |row|
  if(index == 0)
    columns = row.select do |x| x != nil end
  else
    cleaner_row = {}
    columns.each_with_index do |item, index|
      cleaner_row[item.chomp.strip] = row[index]
    end
    dirty_data << cleaner_row
  end
  index = index + 1
end

#1.9.3p327 :128 > dirty_data.size
# => 489184
# 489184 corporations? That seems high. 
# let's look at the last row.
# 1.9.3p327 :129 > dirty_data.last
# => {"DateCreated"=>nil, "CorpRegisterIndex"=>nil, "CorpName"=>nil, "CorpClass"=>nil, "CorpType"=>nil, "Jurisdiction"=>nil, "NatureOfService"=>nil, "OrganizationFormType"=>nil, "StockClass"=>nil, "StockCount"=>nil, "ToDate"=>nil, "Limitations"=>nil, "ParValue"=>nil, "IsNoParValue"=>nil, "IsLimitationByDirectors"=>nil, "StreetAddress1"=>nil, "StreetAddress2"=>nil, "StreetCity"=>nil, "StreetState"=>nil, "StreetProvince"=>nil, "StreetProvince2"=>nil, "MailingAddress1"=>nil, "MailingAddress2"=>nil, "MailingCity"=>nil, "MailingState"=>nil, "MailingProvince"=>nil, "MailingProvince3"=>nil}
# Yep. There are rows that are completely empty. Let's get rid of those by defining some required attributes.
# I'd say a corporation is valid if it has a name (CorpName) and an index of registry (CorpRegisterIndex).

required = ["CorpName", "CorpRegisterIndex"]
less_dirty_data = dirty_data.select do |row|
  valid = true
  row.keys.each do |column|
    unless required.index(column) == nil
      if row[column] == nil
        valid = false
      end
    end
  end
  valid
end

# 1.9.3p327 :331 > less_dirty_data.size
#  => 287387

# that reduced it a bit.

#now, for analytics purposes, it may be nice to have some clean city data. Let's look at mailingCity values. 
# There should be something close to 78 cities/municipalities. 

cities = less_dirty_data.map do |item| item["StreetCity"] || "UNKNOWN" end.sort.uniq

# 1.9.3p327 :339 > cities.size
#  => 1380
#Not even close. 
# Looking at the data, there's a lot of incongruences. Capitalized names, double spaces, accents some times.
# e.g.: "San jUan", "San jUan,", "San jaun", "San jaun,", "San juN", "San juan", "San juan "
# We can clean most of this by lowercasing verything, removing extra spaces and removing accents.

#you need active support for this, so `gem install activesupport` if you don't have it. 
require 'rubygems'
require 'active_support/all'

cleaner_cities = cities.map do |city|
  city = city.force_encoding('iso-8859-1').encode('utf-8').downcase.squeeze(" ").chomp.strip
  city = ActiveSupport::Multibyte::Chars.new(city).
    mb_chars.normalize(:kd).gsub(/[^\x‌​00-\x7F]/n,'').downcase.to_s
  city = city.chomp(",").chomp(".")
  city = city.reverse.chomp(",").chomp(".").reverse
end.sort.uniq

# 1.9.3p327 :096 > cleaner_cities.size
#  => 751 
# Not awesome, but maybe good enough for now. Let's get some stats by normalizing this. 
# I'll abstract the normalization into a function first, then group by and count how many 
# records do we have by city. 

def normalize_pueblo(city)
  city = city.force_encoding('iso-8859-1').encode('utf-8').downcase.squeeze(" ").chomp.strip
  city = ActiveSupport::Multibyte::Chars.new(city).
    mb_chars.normalize(:kd).gsub(/[^\x‌​00-\x7F]/n,'').downcase.to_s
  city = city.chomp(",").chomp(".")
  city = city.reverse.chomp(",").chomp(".").reverse
  city
end

city_counts = []
grouped = less_dirty_data.group_by do |item| 
  normalize_pueblo(item["StreetCity"] || item["MailingCity"] || "UNKNOWN") 
end.each do |clean_city, values|
  city_counts << {:city => clean_city, :records => values.size}
end

# Some quick inspection shows that the top ~100 cities with most records look legit. 
# 1.9.3p327 :149 > city_counts.sort do |a,b| b[:records] <=> a[:records] end.select do |item| item[:city] != "unknown" and item[:city] != "null" end[0..97].map do |item| item[:city] end
#   => ["san juan", "bayamon", "guaynabo", "carolina", "caguas", "ponce", "mayaguez", "toa baja", "trujillo alto", "arecibo", "dorado", "humacao", "toa alta", "vega baja", "aguadilla", "hato rey", "rio piedras", "gurabo", "manati", "guayama", "rio grande", "fajardo", "cayey", "cabo rojo", "isabela", "canovanas", "cidra", "catano", "vega alta", "santurce", "hatillo", "san sebastian", "las piedras", "aguada", "juncos", "yauco", "corozal", "san german", "juana diaz", "moca", "camuy", "coamo", "san lorenzo", "aguas buenas", "luquillo", "naguabo", "salinas", "aibonito", "naranjito", "yabucoa", "anasco", "hormigueros", "barceloneta", "lares", "barranquitas", "rincon", "lajas", "quebradillas", "morovis", "vieques", "santa isabel", "utuado", "loiza", "sabana grande", "arroyo", "orocovis", "ciales", "old san juan", "penuelas", "patillas", "adjuntas", "villalba", "ceiba", "guayanilla", "guanica", "coto laurel", "comerio", "jayuya", "florida", "maunabo", "sanjuan", "las marias", "puerto nuevo", "levittown", "condado", "culebra", "sabana seca", "boqueron", "maricao", "isla verde", "saint just", "aguirre", "mercedita", "ensenada", "miramar", "riopiedras", "cupey", "new york"] 
# 1.9.3p327 :137 > 
# Let's geek out a bit now. There's this thing called [Levenshtein_distance](http://en.wikipedia.org/wiki/Levenshtein_distance)
# that we can use to calculate the similarity between two strings. The lower the number, the more similar they are.
# In this dataset, much of the inconsistencies come from typos (see San Juan vs. San Juann). This can be detected
# by calculating the distance between legit names (top ~100 in ```city_counts```) and all the records. 

# you need to install ```levenshtein-ffi``` by running ```gem install levenshtein-ffi```. You may need to 
# run ```gem install ffi``` first.

# here's a simple example for san juan
require 'levenshtein-ffi'
city = "san juan"
distances = cleaner_cities.map do |a| {:city=>a, :distance => Levenshtein.distance(city, a)} end
distances.select do |a| a[:distance] <= 1 end.map do |c| c[:city] end

# 1.9.3p327 :148 > distances.select do |a| a[:d] <= 1 end.map do |c| c[:city] end 
#   => ["`san juan", "dsan juan", "psan juan", "sa juan", "sab juan", "sabn juan", "sam juan", "san jaun", "san jua", "san jua n", "san juaj", "san juam", "san juan", "san juan'", "san juanm", "san juann", "san juian", "san jun", "san juna", "san uan", "san uuan", "sanb juan", "sanjuan", "sann juan", "sasn juan", "sn juan", "sna juan", "ssan juan"] 

# See? [Magic](http://i.imgur.com/UmpOi.gif).
# Now let's run this in the entire dataset. First we'll make a map where the key will be the dubious city
# and the value will be the legit city based in this calculation. 

legit_cities = city_counts.sort do |a,b| 
  b[:records] <=> a[:records] 
end.select do |item| item[:city] != "unknown" and item[:city] != "null" end[0..97].map do |item| item[:city] end;

cities_map = {}
legit_cities.each do |city|
  distances = cleaner_cities.map do |a| {:city=>a, :distance => Levenshtein.distance(city, a)} end
  similar = distances.select do |a| a[:distance] <= 1 end.map do |c| c[:city] end
  similar.each do |s|
    cities_map[s] = city
  end
end

# let's see:
# 1.9.3p327 :215 > cities_map["psan juan"]
# => "san juan" 
# another one:
# 1.9.3p327 :223 >   cities_map["barranquites"]
#  => "barranquitas" 
# hashtag triunfo!!!

# Let's run this mapping in the entire dataset, adding a column named "PredictedCity" 
# so we don't override the original one, in case we mess up. I'll also use "MailingCity" as 
# a fallback in case there's no StreetCity. 

cleaner_data = less_dirty_data.map do |row|
  row["PredictedCity"] = cities_map[normalize_pueblo(row["StreetCity"] || row["MailingCity"] || "UNKNOWN")]
  row
end

#Now let's see how many unique predicted cities we have: 

# 1.9.3p327 :232 > cleaner_data.map do |item| item["PredictedCity"] || "UNKNOWN" end.sort.uniq.size
#  => 98 

#Kinda obvious. 

# Now let's save our hopefully cleaner dataset. I prefer tab separated files, so I'm gonna do that. 
columns << "PredictedCity"

tsv_string = columns.join("\t") + "\n"
cleaner_data.each do |item|
  row = []
  columns.each do |column|
    cell = item[column]
    unless cell == nil || cell.downcase == "unknown" || cell.downcase == "null"
      row << item[column].gsub("\t", " ")
    else
      row << ""
    end    
  end
  tsv_string << row.join("\t") + "\n"
end
w = File.open("/Users/miguel/Dropbox/cleaner_corps.tsv", "w")
w.write(tsv_string)
w.close
#The end. 
