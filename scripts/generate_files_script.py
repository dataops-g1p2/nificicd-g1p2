import csv
import os
import random
import string
import time
from datetime import datetime

# 📂 Dossier de destination (ton répertoire NiFi)
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "..", "inputs")

# 🔤 Quelques caractères spéciaux à insérer pour "salir" les données
SPECIAL_CHARS = ['§', 'ñ', '💥', 'ç', 'ø', 'ü', '©', 'é', '!', '✅', '@@@', '###', '***', '~', '☺']

# 💡 Génère une chaîne de texte aléatoire avec des caractères spéciaux
def random_dirty_text(base_text):
    dirty = base_text
    for _ in range(random.randint(1, 3)):
        dirty += random.choice(SPECIAL_CHARS)
    return dirty

# 🧩 Fonction pour créer un fichier CSV avec des données sales
def generate_dirty_csv():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"input_{timestamp}.csv"
    filepath = os.path.join(OUTPUT_DIR, filename)

    headers = ["ID", "first_name", "last_name", "email", "phone_number", "address", "dob", "amount", "notes"]

    rows = []
    for i in range(1, 6):
        row = {
            "ID": i,
            "first_name": random_dirty_text(random.choice(["Omar", "Fatima", "Youssef", "Sara", "Leila"])),
            "last_name": random_dirty_text(random.choice(["Cherkaoui", "Ben Ali", "El Idrissi", "Laaziri"])),
            "email": random_dirty_text(f"{random.choice(['omar', 'fatima', 'youssef', 'sara', 'leila']).lower()}@test_org.com"),
            "phone_number": random_dirty_text(f"0{random.randint(600000000, 799999999)}"),
            "address": random_dirty_text(f"{random.randint(100, 299)} Rue {random.choice(['Industriel', 'Mohammed V', 'Hassan II'])}"),
            "dob": random_dirty_text(f"{random.randint(1970, 2024)}-{random.randint(1,12):02d}-{random.randint(1,28):02d}"),
            "amount": random_dirty_text(str(round(random.uniform(100, 1000), 2))),
            "notes": random_dirty_text(random.choice(["nouveau client", "client fidèle", "vérifier adresse", "à recontacter"]))
        }
        rows.append(row)

    with open(filepath, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=headers)
        writer.writeheader()
        writer.writerows(rows)

    print(f"✅ Fichier généré : {filepath}")

# 🚀 Génère un fichier toutes les 30 secondes
if __name__ == "__main__":
    print(f"🚀 Génération automatique des fichiers sales dans : {OUTPUT_DIR}")
    while True:
        generate_dirty_csv()
        time.sleep(30)
