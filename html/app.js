const app = document.getElementById('app');
const closeButton = document.getElementById('close');
const weatherGrid = document.getElementById('weather-grid');
const logsContainer = document.getElementById('logs');
const hourInput = document.getElementById('hour');
const minuteInput = document.getElementById('minute');
const setTimeButton = document.getElementById('set-time');
const tempCurrent = document.getElementById('temp-current');
const tempWeather = document.getElementById('temp-weather');
const tempAltitude = document.getElementById('temp-altitude');
const voteGrid = document.getElementById('vote-grid');
const voteStats = document.getElementById('vote-stats');
const voteStatus = document.getElementById('vote-status');
const startVoteButton = document.getElementById('start-vote');
const scheduleList = document.getElementById('schedule-list');
const scheduleHour = document.getElementById('schedule-hour');
const scheduleMinute = document.getElementById('schedule-minute');
const scheduleWeather = document.getElementById('schedule-weather');
const scheduleTemp = document.getElementById('schedule-temp');
const scheduleRain = document.getElementById('schedule-rain');
const scheduleFog = document.getElementById('schedule-fog');
const scheduleWind = document.getElementById('schedule-wind');
const scheduleRecurring = document.getElementById('schedule-recurring');
const addScheduleButton = document.getElementById('add-schedule');

const menuItems = document.querySelectorAll('.menu-item');
const sections = document.querySelectorAll('.section');
const sectionTitle = document.getElementById('section-title');

const freezeButtons = [
  document.getElementById('freeze-weather'),
  document.getElementById('freeze-weather-alt')
];

const timeFreezeButtons = [
  document.getElementById('freeze-time'),
  document.getElementById('freeze-time-alt')
];

const weatherIcons = {
  CLEAR: '☀️',
  EXTRASUNNY: '🌞',
  CLOUDS: '☁️',
  OVERCAST: '🌥️',
  RAIN: '🌧️',
  THUNDER: '⛈️',
  CLEARING: '🌤️',
  SMOG: '🌫️',
  FOGGY: '🌁',
  SNOW: '❄️',
  BLIZZARD: '🌨️',
  XMAS: '🎄'
};

let currentState = null;
let weatherCards = {};
let weatherOptions = [];

const resourceName = () => {
  if (typeof GetParentResourceName === 'function') {
    return GetParentResourceName();
  }
  return 'hawes-weather';
};

const safePost = (event, payload = {}) => {
  if (typeof fetch !== 'function') return;
  fetch(`https://${resourceName()}/${event}`, {
    method: 'POST',
    body: JSON.stringify(payload)
  }).catch(() => {});
};

function switchSection(target) {
  sections.forEach((section) => {
    section.classList.toggle('active', section.id === target);
  });

  menuItems.forEach((item) => {
    item.classList.toggle('active', item.dataset.section === target);
  });

  const titles = {
    weather: 'Weather Control',
    temperature: 'Temperature',
    voting: 'Voting',
    scheduler: 'Scheduler',
    freeze: 'Freeze Panel',
    logs: 'System Logs'
  };
  sectionTitle.textContent = titles[target] || 'Weather Control';
}

menuItems.forEach((item) => {
  item.addEventListener('click', () => switchSection(item.dataset.section));
});

closeButton.addEventListener('click', () => {
  safePost('close');
  app.classList.add('hidden');
});

setTimeButton.addEventListener('click', () => {
  const hour = parseInt(hourInput.value || '0', 10);
  const minute = parseInt(minuteInput.value || '0', 10);
  safePost('setTime', { hour, minute });
});

freezeButtons.forEach((button) => {
  if (!button) return;
  button.addEventListener('click', () => {
    safePost('toggleFreezeWeather');
  });
});

timeFreezeButtons.forEach((button) => {
  if (!button) return;
  button.addEventListener('click', () => {
    safePost('toggleFreezeTime');
  });
});

startVoteButton.addEventListener('click', () => {
  safePost('startVote', { reason: 'Manual Vote' });
});

addScheduleButton.addEventListener('click', () => {
  safePost('addSchedule', {
    hour: parseInt(scheduleHour.value || '0', 10),
    minute: parseInt(scheduleMinute.value || '0', 10),
    weather: scheduleWeather.value,
    temp: scheduleTemp.value ? parseFloat(scheduleTemp.value) : null,
    rain: scheduleRain.value ? parseInt(scheduleRain.value, 10) : 0,
    fog: scheduleFog.value ? parseInt(scheduleFog.value, 10) : 0,
    wind: scheduleWind.value ? parseInt(scheduleWind.value, 10) : 0,
    recurring: scheduleRecurring.value === 'true'
  });
});

function renderWeatherCards(weathers, selected, container = weatherGrid, enableVote = false) {
  container.innerHTML = '';

  weathers.forEach((weather) => {
    const card = document.createElement('button');
    card.className = 'weather-card';
    card.innerHTML = `
      <div class="icon">${weatherIcons[weather.id] || '🌤️'}</div>
      <strong>${weather.label}</strong>
      <span>${weather.description}</span>
    `;
    card.addEventListener('click', () => {
      if (enableVote) {
        safePost('castVote', { weather: weather.id });
        return;
      }
      safePost('setWeather', { weather: weather.id });
    });
    container.appendChild(card);
    if (container === weatherGrid) {
      weatherCards[weather.id] = card;
    }
  });

  if (container === weatherGrid) {
    updateSelectedWeather(selected);
  }
}

function updateSelectedWeather(weatherId) {
  Object.entries(weatherCards).forEach(([id, card]) => {
    card.classList.toggle('active', id === weatherId);
  });
}

function renderLogs(logs) {
  logsContainer.innerHTML = '';
  logs.forEach((entry) => {
    const logItem = document.createElement('div');
    logItem.className = 'log-item';
    logItem.innerHTML = `
      <div class="time">${entry.time}</div>
      <div>
        <span class="badge">${entry.actor}</span>
        <strong>${entry.action}</strong> — ${entry.detail}
      </div>
    `;
    logsContainer.appendChild(logItem);
  });
}

function renderSchedules(items) {
  scheduleList.innerHTML = '';
  items.forEach((item) => {
    const row = document.createElement('div');
    row.className = 'schedule-item';
    row.innerHTML = `
      <div>
        <strong>${item.hour.toString().padStart(2, '0')}:${item.minute.toString().padStart(2, '0')}</strong>
        <span class="muted">${item.weather} · ${item.recurring ? 'Daily' : 'Once'}</span>
      </div>
      <button data-id="${item.id}">Delete</button>
    `;
    row.querySelector('button').addEventListener('click', () => {
      safePost('deleteSchedule', { id: item.id });
    });
    scheduleList.appendChild(row);
  });
}

function renderVote(vote) {
  voteStats.innerHTML = '';
  if (!vote) {
    voteStatus.textContent = 'No active vote.';
    voteGrid.innerHTML = '';
    return;
  }

  const endsIn = Math.max(0, vote.endsAt - Math.floor(Date.now() / 1000));
  voteStatus.textContent = `Vote ends in ${endsIn}s. Reason: ${vote.reason}`;

  const tally = {};
  Object.values(vote.votes || {}).forEach((weather) => {
    tally[weather] = (tally[weather] || 0) + 1;
  });

  Object.entries(tally).forEach(([weather, count]) => {
    const card = document.createElement('div');
    card.className = 'stat-card';
    card.innerHTML = `<span>${weather}</span><strong>${count} votes</strong>`;
    voteStats.appendChild(card);
  });

  const optionObjects = weatherOptions.filter((option) => vote.options.includes(option.id));
  renderWeatherCards(optionObjects, null, voteGrid, true);
}

function updateTemperature(temp) {
  if (tempCurrent) {
    tempCurrent.textContent = `${temp}°C`;
  }
  if (currentState && tempWeather) {
    tempWeather.textContent = currentState.weather;
  }
  if (tempAltitude) {
    tempAltitude.textContent = `${Math.round((currentState?.altitude || 0))}m`;
  }
}

function renderWeatherSelect(weathers) {
  scheduleWeather.innerHTML = '';
  weathers.forEach((weather) => {
    const option = document.createElement('option');
    option.value = weather.id;
    option.textContent = weather.label;
    scheduleWeather.appendChild(option);
  });
}

function applyState(state, logs) {
  currentState = state;
  hourInput.value = state.hour;
  minuteInput.value = state.minute;
  updateSelectedWeather(state.weather);
  renderLogs(logs || []);
  renderSchedules(state.schedules || []);
  renderVote(state.voteState || null);
  updateTemperature(state.temperature || 20);
}

window.addEventListener('message', (event) => {
  const data = event.data;
  if (data.type === 'close') {
    app.classList.add('hidden');
    return;
  }
  if (data.type === 'open') {
    app.classList.remove('hidden');
    return;
  }

  if (data.type === 'state') {
    weatherOptions = data.state.weatherTypes || [];
    renderWeatherCards(weatherOptions, data.state.weather);
    renderWeatherSelect(weatherOptions);
    applyState(data.state, data.logs);
  }

  if (data.type === 'logs') {
    renderLogs(data.logs || []);
  }

  if (data.type === 'schedules') {
    renderSchedules(data.schedules || []);
  }

  if (data.type === 'vote') {
    renderVote(data.vote);
  }

  if (data.type === 'voteEnd') {
    renderVote(null);
  }

  if (data.type === 'temperature') {
    updateTemperature(data.temperature);
  }
});

safePost('ready');
