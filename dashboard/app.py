from flask import Flask, render_template, request, redirect, session
import docker
import os

app = Flask(__name__)
app.secret_key = 'supersecretkey'

ENV_FILE = "/app/.env"
CONTAINERS = ["ukk_database", "ukk_phpmyadmin"]
HOST_PROJECT_PATH = os.environ.get("HOST_PROJECT_PATH", "/app")
COMPOSE_PROJECT_NAME = "setup-db-ukk" 

def read_env():
    env_data = {}
    if os.path.exists(ENV_FILE):
        with open(ENV_FILE, 'r') as f:
            for line in f:
                if '=' in line and not line.startswith('#'):
                    k, v = line.strip().split('=', 1)
                    v = v.strip('"').strip("'")
                    env_data[k] = v
    return env_data

def write_env(data):
    with open(ENV_FILE, 'w') as f:
        for k, v in data.items():
            f.write(f"{k}={v}\n")

def get_docker_client():
    return docker.from_env()

def stop_and_remove(client, name):
    try:
        c = client.containers.get(name)
        c.stop(timeout=10)
        c.remove(v=True)
    except docker.errors.NotFound:
        pass

def start_containers(client, env):
    network_name = "ukk_network"
    networks = [n.name for n in client.networks.list()]
    if network_name not in networks:
        client.networks.create(network_name, driver="bridge")

    client.containers.run(
        image="mysql:latest",
        name="ukk_database",
        detach=True,
        restart_policy={"Name": "always"},
        environment={
            "MYSQL_ROOT_PASSWORD": env.get("DB_ROOT_PASSWORD"),
            "STUDENT_DATA": env.get("STUDENT_DATA"),
            "OUTPUT_FILENAME": env.get("OUTPUT_FILE"),
            "SHEET_API_URL": env.get("SHEET_API_URL"),
            "EVENT": env.get("EVENT"),
        },
        ports={"3306/tcp": int(env.get("DB_BASE_PORT", 3306))},
        volumes={
            f"{HOST_PROJECT_PATH}/init-db.sh": {"bind": "/docker-entrypoint-initdb.d/init-db.sh", "mode": "ro"},
            f"{HOST_PROJECT_PATH}/output": {"bind": "/mnt/kredensial", "mode": "rw"},
        },
        mem_limit=env.get("CONTAINER_MEMORY", "512m"),
        nano_cpus=int(float(env.get("CONTAINER_CPUS", "1")) * 1e9),
        network=network_name,
        labels={
            "com.docker.compose.project": COMPOSE_PROJECT_NAME,
            "com.docker.compose.service": "ukk_database",
            "com.docker.compose.oneoff": "False"
        }
    )

    client.containers.run(
        image="phpmyadmin:latest",
        name="ukk_phpmyadmin",
        detach=True,
        restart_policy={"Name": "always"},
        environment={
            "PMA_HOST": "ukk_database",
            "PMA_ARBITRARY": "0",
            "PMA_VERBOSE": "UKK_DB_SERVER",
        },
        ports={"80/tcp": int(env.get("PMA_BASE_PORT", 8080))},
        network=network_name,
        labels={
            "com.docker.compose.project": COMPOSE_PROJECT_NAME,
            "com.docker.compose.service": "phpmyadmin",
            "com.docker.compose.oneoff": "False"
        }
    )

@app.route('/', methods=['GET', 'POST'])
def login():
    env = read_env()
    dash_pass = env.get('DASHBOARD_PASSWORD', env.get('DB_ROOT_PASSWORD', 'admin123'))
    error_msg = ""
    
    if request.method == 'POST':
        if request.form.get('password') == dash_pass:
            session['logged_in'] = True
            return redirect('/admin')
        error_msg = '<div class="alert alert-danger" role="alert">Password Dashboard Salah!</div>'
        
    return f'''
        <!DOCTYPE html>
        <html>
        <head>
            <title>Login - Dashboard Konfigurasi UKK Database</title>
            <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
        </head>
        <body class="bg-light d-flex align-items-center justify-content-center" style="height: 100vh;">
            <div class="card shadow border-0" style="width: 380px; border-radius: 15px;">
                <div class="card-body p-4 text-center">
                    <h3 class="mb-4 text-primary fw-bold">Login</h3>
                    {error_msg}
                    <form method="post">
                        <div class="mb-3">
                            <input type="password" name="password" class="form-control form-control-lg" placeholder="Dashboard Password...." required>
                        </div>
                        <button type="submit" class="btn btn-primary btn-lg w-100 fw-bold">Login</button>
                    </form>
                    <p class="mt-3 text-muted small">Dashboard Konfigurasi UKK Database</p>
                </div>
            </div>
        </body>
        </html>
    '''

@app.route('/admin', methods=['GET', 'POST'])
def admin():
    if not session.get('logged_in'):
        return redirect('/')
    old_env = read_env()
    if request.method == 'POST':
        new_env = {
            'DB_ROOT_PASSWORD': request.form.get('DB_ROOT_PASSWORD') or old_env.get('DB_ROOT_PASSWORD'),
            'DASHBOARD_PASSWORD': request.form.get('DASHBOARD_PASSWORD') or old_env.get('DASHBOARD_PASSWORD'),
            'STUDENT_DATA': request.form.get('STUDENT_DATA') or old_env.get('STUDENT_DATA'),
            'EVENT': request.form.get('EVENT') or old_env.get('EVENT'),
            'PMA_BASE_PORT': request.form.get('PMA_BASE_PORT') or old_env.get('PMA_BASE_PORT'),
            'DB_BASE_PORT': request.form.get('DB_BASE_PORT') or old_env.get('DB_BASE_PORT'),
            'CONTAINER_MEMORY': request.form.get('CONTAINER_MEMORY') or old_env.get('CONTAINER_MEMORY'),
            'CONTAINER_CPUS': request.form.get('CONTAINER_CPUS') or old_env.get('CONTAINER_CPUS'),
            'OUTPUT_FILE': request.form.get('OUTPUT_FILE') or old_env.get('OUTPUT_FILE'),
            'SHEET_API_URL': request.form.get('SHEET_API_URL') or old_env.get('SHEET_API_URL')
        }
        write_env(new_env)
        try:
            client = get_docker_client()
            for name in CONTAINERS:
                stop_and_remove(client, name)
            start_containers(client, new_env)
            return '''
                <!DOCTYPE html>
                <html>
                <head>
                    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
                </head>
                <body class="bg-light d-flex align-items-center justify-content-center" style="height: 100vh;">
                    <div class="card shadow border-0 p-5 text-center" style="border-radius: 15px; max-width: 500px;">
                        <h2 class="text-success mb-3">✅ Berhasil!</h2>
                        <p class="text-secondary mb-4">Konfigurasi berhasil disimpan dan Container sedang di-reset ulang. Proses ini memakan waktu beberapa detik.</p>
                        <a href="/admin" class="btn btn-outline-primary btn-lg">Kembali ke Dashboard</a>
                    </div>
                </body>
                </html>
            '''
        except Exception as e:
            return f'''
                <!DOCTYPE html>
                <html>
                <head>
                    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
                </head>
                <body class="bg-light d-flex align-items-center justify-content-center" style="height: 100vh;">
                    <div class="card shadow border-0 p-5" style="border-radius: 15px; max-width: 600px;">
                        <h2 class="text-danger text-center mb-3">❌ Terjadi Error</h2>
                        <div class="bg-dark text-light p-3 rounded mb-4" style="overflow-x: auto;"><pre>{e}</pre></div>
                        <a href="/admin" class="btn btn-outline-danger btn-lg w-100">Kembali ke Dashboard</a>
                    </div>
                </body>
                </html>
            '''
    return render_template('index.html', env=old_env)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8888)