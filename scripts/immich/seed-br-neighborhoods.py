#!/usr/bin/env python3
"""
seed-br-neighborhoods.py

Adiciona bairros brasileiros (capitais + regiões metropolitanas) na tabela
`geodata_places` do Immich, complementando a base padrão do GeoNames que só
tem cidades (`cities500`) e por isso erra ao geocodar coordenadas dentro de
bairros grandes (ex: Lagoa/RJ vira Leblon).

Fonte: OSM via Overpass API (`place=suburb|neighbourhood|quarter`).

Uso:
  # Gera SQL (não aplica):
  python3 seed-br-neighborhoods.py > /tmp/br-neighborhoods.sql

  # Aplica no Postgres do Immich (dentro do CT 103):
  sudo -u postgres psql -d immich -f /tmp/br-neighborhoods.sql
  systemctl restart immich-web

Regenerar após update do Immich (que pode resetar geodata_places):
  Reexecutar os passos acima. IDs partem de 90000001 (safe zone).
"""

import json
import sys
import time
import urllib.request
import urllib.parse
from datetime import date

OVERPASS_URL = "https://overpass-api.de/api/interpreter"
ID_START = 90000001   # safe zone acima do máximo do GeoNames (~11M)
MOD_DATE = date.today().isoformat()

# admin1Code do GeoNames por UF (não é o código IBGE; é interno do GeoNames)
UF_ADMIN1 = {
    "AC": ("01", "Acre"),               "AL": ("02", "Alagoas"),
    "AP": ("03", "Amapá"),              "AM": ("04", "Amazonas"),
    "BA": ("05", "Bahia"),              "CE": ("06", "Ceará"),
    "DF": ("07", "Distrito Federal"),   "ES": ("08", "Espírito Santo"),
    "GO": ("29", "Goiás"),              "MA": ("13", "Maranhão"),
    "MT": ("14", "Mato Grosso"),        "MS": ("11", "Mato Grosso do Sul"),
    "MG": ("15", "Minas Gerais"),       "PA": ("16", "Pará"),
    "PB": ("17", "Paraíba"),            "PR": ("18", "Paraná"),
    "PE": ("19", "Pernambuco"),         "PI": ("20", "Piauí"),
    "RJ": ("21", "Rio de Janeiro"),     "RN": ("22", "Rio Grande do Norte"),
    "RS": ("23", "Rio Grande do Sul"),  "RO": ("24", "Rondônia"),
    "RR": ("25", "Roraima"),            "SC": ("26", "Santa Catarina"),
    "SP": ("27", "São Paulo"),          "SE": ("28", "Sergipe"),
    "TO": ("31", "Tocantins"),
}

# (nome do município no OSM, UF, código IBGE 7 dígitos)
MUNICIPALITIES = [
    # === 27 capitais ===
    ("Rio Branco", "AC", "1200401"),
    ("Maceió", "AL", "2704302"),
    ("Macapá", "AP", "1600303"),
    ("Manaus", "AM", "1302603"),
    ("Salvador", "BA", "2927408"),
    ("Fortaleza", "CE", "2304400"),
    ("Brasília", "DF", "5300108"),
    ("Vitória", "ES", "3205309"),
    ("Goiânia", "GO", "5208707"),
    ("São Luís", "MA", "2111300"),
    ("Cuiabá", "MT", "5103403"),
    ("Campo Grande", "MS", "5002704"),
    ("Belo Horizonte", "MG", "3106200"),
    ("Belém", "PA", "1501402"),
    ("João Pessoa", "PB", "2507507"),
    ("Curitiba", "PR", "4106902"),
    ("Recife", "PE", "2611606"),
    ("Teresina", "PI", "2211001"),
    ("Rio de Janeiro", "RJ", "3304557"),
    ("Natal", "RN", "2408102"),
    ("Porto Alegre", "RS", "4314902"),
    ("Porto Velho", "RO", "1100205"),
    ("Boa Vista", "RR", "1400100"),
    ("Florianópolis", "SC", "4205407"),
    ("São Paulo", "SP", "3550308"),
    ("Aracaju", "SE", "2800308"),
    ("Palmas", "TO", "1721000"),

    # === Municípios de RMs importantes ===
    # Grande Rio
    ("Niterói", "RJ", "3303302"),
    ("Duque de Caxias", "RJ", "3301702"),
    ("Nova Iguaçu", "RJ", "3303500"),
    ("São Gonçalo", "RJ", "3304904"),
    ("Petrópolis", "RJ", "3303906"),
    # ABC + Grande SP
    ("São Bernardo do Campo", "SP", "3548708"),
    ("Santo André", "SP", "3547809"),
    ("Guarulhos", "SP", "3518800"),
    ("Osasco", "SP", "3534401"),
    ("Campinas", "SP", "3509502"),
    ("Santos", "SP", "3548500"),
    ("São José dos Campos", "SP", "3549904"),
    ("Sorocaba", "SP", "3552205"),
    ("Ribeirão Preto", "SP", "3543402"),
    # Grande BH
    ("Contagem", "MG", "3118601"),
    ("Betim", "MG", "3106705"),
    ("Uberlândia", "MG", "3170206"),
    # Grande Recife
    ("Olinda", "PE", "2609600"),
    ("Jaboatão dos Guararapes", "PE", "2607901"),
    # Grande Curitiba
    ("São José dos Pinhais", "PR", "4125506"),
    ("Londrina", "PR", "4113700"),
    # Grande Vitória
    ("Serra", "ES", "3205000"),
    ("Vila Velha", "ES", "3205200"),
    ("Cariacica", "ES", "3201308"),
    # Grande POA
    ("Canoas", "RS", "4304606"),
    ("Novo Hamburgo", "RS", "4313409"),
    # Grande Salvador
    ("Feira de Santana", "BA", "2910800"),
]


def overpass_query(city_name: str, uf: str) -> list[dict]:
    """
    Consulta Overpass API pedindo bairros dentro do admin_level=8 de um município.
    Retorna lista de dicts com {name, lat, lng}.
    """
    query = f"""
    [out:json][timeout:120];
    area["admin_level"="8"]["name"="{city_name}"]["is_in:state_code"~"BR-{uf}"]->.city;
    (
      node["place"~"^(suburb|neighbourhood|quarter)$"]["name"](area.city);
    );
    out center;
    """
    # Fallback: alguns municípios não têm is_in:state_code — usa ISO3166-2
    fallback = f"""
    [out:json][timeout:120];
    area["ISO3166-2"="BR-{uf}"]["admin_level"="4"]->.state;
    area["admin_level"="8"]["name"="{city_name}"](area.state)->.city;
    (
      node["place"~"^(suburb|neighbourhood|quarter)$"]["name"](area.city);
    );
    out center;
    """

    for attempt, q in enumerate((query, fallback), 1):
        try:
            data = urllib.parse.urlencode({"data": q}).encode()
            req = urllib.request.Request(OVERPASS_URL, data=data)
            with urllib.request.urlopen(req, timeout=180) as resp:
                payload = json.loads(resp.read().decode("utf-8"))
            elements = payload.get("elements", [])
            if elements:
                return [
                    {"name": e["tags"]["name"], "lat": e["lat"], "lng": e["lon"]}
                    for e in elements
                    if e.get("tags", {}).get("name")
                ]
        except Exception as e:
            print(f"-- WARN: attempt {attempt} for {city_name}/{uf}: {e}", file=sys.stderr)
        time.sleep(2)
    return []


def escape_sql(v: str) -> str:
    return v.replace("'", "''")


def main() -> int:
    print("-- Bairros brasileiros para complementar cities500 do Immich")
    print(f"-- Gerado em: {MOD_DATE}")
    print(f"-- Total de municípios consultados: {len(MUNICIPALITIES)}")
    print()
    print("BEGIN;")
    print()

    seen: set[tuple[str, str]] = set()
    next_id = ID_START
    total_inserted = 0

    for i, (city, uf, ibge) in enumerate(MUNICIPALITIES, 1):
        admin1_code, admin1_name = UF_ADMIN1[uf]
        print(f"-- [{i}/{len(MUNICIPALITIES)}] {city}/{uf}", file=sys.stderr)
        neighborhoods = overpass_query(city, uf)
        print(f"--    {len(neighborhoods)} bairros retornados pela Overpass", file=sys.stderr)

        for n in neighborhoods:
            key = (n["name"].lower(), city)
            if key in seen:
                continue
            seen.add(key)

            print(
                f"INSERT INTO geodata_places "
                f"(id, name, latitude, longitude, \"countryCode\", \"admin1Code\", \"admin2Code\", "
                f"\"admin1Name\", \"admin2Name\", \"modificationDate\") "
                f"VALUES ({next_id}, '{escape_sql(n['name'])[:200]}', {n['lat']}, {n['lng']}, "
                f"'BR', '{admin1_code}', '{ibge}', '{escape_sql(admin1_name)}', '{escape_sql(city)}', "
                f"'{MOD_DATE}') ON CONFLICT (id) DO NOTHING;"
            )
            next_id += 1
            total_inserted += 1

        # Rate limiting: Overpass pede ~1 req/s
        time.sleep(2)

    print()
    print("COMMIT;")
    print()
    print(f"-- Total de linhas inseridas: {total_inserted}", file=sys.stderr)
    print(f"-- Total de linhas inseridas: {total_inserted}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
